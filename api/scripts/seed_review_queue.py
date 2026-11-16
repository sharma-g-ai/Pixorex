# ruff: noqa: S101, S311, E501
"""Demo data for trying delegation: other technicians and scans waiting in the review queue.
Local database only.

Adds technicians to one unit (Tara, Rohan, Meera, Priya, Karan and Sana Demo; --only picks some, --no-scans adds just them) and, on every run, 9 scans
that they submitted and nobody has reviewed yet ("waiting for approval"). The scans are
different ages (30 minutes up to 15 days) so the queue shows the oldest first, and some
are over 1 day and over 1 week old. A BU Admin can open them, decide them, or delegate them.

The technicians exist only in the database after this script. Run
keycloak/scripts/kc-seed-technicians.ps1 to give them logins.

Run after migrations, as the owner role (from the api folder):
    PIXOREX_MIGRATIONS_DATABASE_URL=postgresql://pixorex_owner:local-only@localhost:5433/pixorex \
        uv run python scripts/seed_review_queue.py [--unit "Motor Plant"]

The technicians are added once (fixed ids); each run adds 9 more scans. The scans reuse photos
that are already stored, so at least one scan with a photo must exist in the unit.
"""

import argparse
import json
import os
import random
import uuid
from datetime import UTC, datetime, timedelta

import psycopg

from app.repositories.scans import PATH_SEPARATOR, record_no_for

TECHNICIANS = [
    (uuid.UUID("7e1d2c3b-0000-4000-8000-000000000030"), "Tara Demo", "tara.demo@demo.local"),
    (uuid.UUID("7e1d2c3b-0000-4000-8000-000000000031"), "Rohan Demo", "rohan.demo@demo.local"),
    (uuid.UUID("7e1d2c3b-0000-4000-8000-000000000032"), "Meera Demo", "meera.demo@demo.local"),
    (uuid.UUID("7e1d2c3b-0000-4000-8000-000000000033"), "Priya Demo", "priya.demo@demo.local"),
    (uuid.UUID("7e1d2c3b-0000-4000-8000-000000000034"), "Karan Demo", "karan.demo@demo.local"),
    (uuid.UUID("7e1d2c3b-0000-4000-8000-000000000035"), "Sana Demo", "sana.demo@demo.local"),
]
# Hours since the technician submitted each scan.
PLAN = [0.5, 3, 9, 20, 30, 50, 6 * 24, 8 * 24, 15 * 24]  # 30 h: over 1 day; 8 days: over 1 week
SAMPLES = {
    "manufacturer": ["U.S. Electrical Motors", "Baldor-Reliance", "Siemens", "ABB"],
    "model": ["PX-7700-T", "ECP8442T", "1LE1001-1CB2", "M3BP 160"],
    "voltage": ["460", "230", "415"],
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--unit", default="Motor Plant", help="business unit name")
    parser.add_argument(
        "--only", help="use only these technicians (first names, comma-separated, e.g. Tara,Priya)"
    )
    parser.add_argument("--no-scans", action="store_true", help="add the technicians only")
    args = parser.parse_args()
    unit_name = args.unit
    technicians = [
        t
        for t in TECHNICIANS
        if not args.only
        or t[1].split()[0].lower() in {n.strip().lower() for n in args.only.split(",")}
    ]
    assert technicians, f"no technician named {args.only}"

    url = os.environ["PIXOREX_MIGRATIONS_DATABASE_URL"]
    assert "localhost" in url, "local database only"
    random.seed(16)
    with psycopg.connect(url) as conn, conn.cursor() as cur:

        def one(sql: str, args: tuple = ()) -> tuple:
            cur.execute(sql, args)
            row = cur.fetchone()
            assert row is not None, f"nothing found for: {sql[:60]}"
            return row

        tenant, bu = one("SELECT tenant_id, id FROM business_unit WHERE name = %s", (unit_name,))
        for tech_id, name, email in technicians:
            cur.execute(
                "INSERT INTO app_user (id, tenant_id, email, full_name, status, last_bu_id)"
                " VALUES (%s, %s, %s, %s, 'active', %s) ON CONFLICT (id) DO NOTHING",
                (tech_id, tenant, email, name, bu),
            )
            cur.execute(
                "INSERT INTO user_unit_role (id, tenant_id, user_id, bu_id, role, is_primary)"
                " SELECT %s, %s, %s, %s, 'field_technician',"
                " NOT EXISTS (SELECT 1 FROM user_unit_role WHERE user_id = %s AND is_primary)"
                " ON CONFLICT (id) DO NOTHING",
                (
                    uuid.uuid5(uuid.NAMESPACE_URL, f"pixorex-seed/role/{tech_id}/{bu}"),
                    tenant,
                    tech_id,
                    bu,
                    tech_id,
                ),
            )

        process = one("SELECT id FROM business_process WHERE bu_id = %s AND is_default", (bu,))[0]
        # The unit's places a technician can scan at: the ones with nothing inside them.
        cur.execute(
            "SELECT n.id, n.name, n.parent_id FROM location_node n"
            " JOIN location_hierarchy_version h ON h.id = n.version_id"
            " WHERE h.bu_id = %s AND h.status = 'published'",
            (bu,),
        )
        nodes = {row[0]: row for row in cur.fetchall()}
        parents = {row[2] for row in nodes.values()}
        places = []
        for node_id in nodes:
            if node_id in parents:
                continue
            names, at = [], node_id
            while at is not None:
                names.append(nodes[at][1])
                at = nodes[at][2]
            places.append((node_id, PATH_SEPARATOR.join(reversed(names))))
        assert places, f"{unit_name} has no published location to scan at"
        # Photos already stored: the unit's own first, then any in the tenant.
        cur.execute(
            "SELECT DISTINCT ON (p.object_key) p.object_key, p.sha256, (s.bu_id = %s) AS own"
            " FROM scan_photo p JOIN scan s ON s.id = p.scan_id WHERE s.tenant_id = %s"
            " ORDER BY p.object_key, own DESC",
            (bu, tenant),
        )
        photos = sorted(cur.fetchall(), key=lambda p: not p[2])[:12]
        assert photos, "no stored photo to reuse; capture one scan first"

        # Every published equipment type of the unit that has an active contract.
        cur.execute(
            "SELECT et.name, et.id, c.id FROM equipment_type et JOIN equipment_type_version etv"
            " ON etv.equipment_type_id = et.id JOIN extraction_contract c ON c.type_version_id = etv.id"
            " WHERE et.bu_id = %s AND et.status = 'published' AND c.status = 'active'"
            " ORDER BY et.name",
            (bu,),
        )
        found = cur.fetchall()
        assert found, f"{unit_name} has no published equipment type"
        types = {}
        for name, type_id, contract in found:
            cur.execute(
                "SELECT fd.id, fd.field_key, fd.label, fd.data_type, fd.is_required, fd.options"
                " FROM field_definition fd JOIN extraction_contract c ON c.type_version_id = fd.type_version_id"
                " WHERE c.id = %s ORDER BY fd.sort_order",
                (contract,),
            )
            types[name] = (type_id, contract, cur.fetchall())

        def value_for(key: str, label: str, data_type: str, options: list | None) -> str:
            if data_type == "dropdown" and options:
                return options[0]
            if data_type == "boolean":
                return "true"
            if data_type == "date":
                return "2024-03-18"
            if data_type == "number":
                return str(random.choice([10, 15, 60, 1765]))
            if "serial" in key:
                return f"SN-{random.randint(100000, 999999)}"
            for part, choices in SAMPLES.items():
                if part in key:
                    return random.choice(choices)
            return f"{label[:3].upper()}-{random.randint(100, 999)}"

        now = datetime.now(UTC)
        added = []
        for i, hours in enumerate([] if args.no_scans else PLAN):
            type_name = list(types)[i % len(types)]
            type_id, contract, fields = types[type_name]
            node, path = places[i % len(places)]
            tech_id, tech_name, _ = technicians[i % len(technicians)]
            submitted = now - timedelta(hours=hours)
            last = one(
                "SELECT max(left(record_no, 9)::bigint) FROM scan"
                " WHERE tenant_id = %s AND record_no ~ '^[0-9]{10}$'",
                (tenant,),
            )[0]
            scan_id, record_no = uuid.uuid4(), record_no_for((last or 0) + 1)
            cur.execute(
                "INSERT INTO scan (id, tenant_id, bu_id, process_id, record_no, client_capture_id,"
                " technician_id, equipment_type_id, contract_id, location_node_id,"
                " location_path_snapshot, processing_status, review_status, captured_at)"
                " VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'ready_to_review','waiting_for_approval',%s)",
                (
                    scan_id,
                    tenant,
                    bu,
                    process,
                    record_no,
                    uuid.uuid4(),
                    tech_id,
                    type_id,
                    contract,
                    node,
                    path,
                    submitted - timedelta(minutes=10),
                ),
            )
            object_key, sha, _own = photos[i % len(photos)]
            cur.execute(
                "INSERT INTO scan_photo (tenant_id, scan_id, photo_no, object_key, sha256)"
                " VALUES (%s,%s,1,%s,%s)",
                (tenant, scan_id, object_key, sha),
            )
            attempt = one(
                "INSERT INTO extraction_attempt (tenant_id, scan_id, attempt_no, contract_id, trigger, status)"
                " VALUES (%s,%s,1,%s,'first','succeeded') RETURNING id",
                (tenant, scan_id, contract),
            )[0]
            ai, verdicts, values = {}, [], {}
            for n, (fid, key, label, dtype, required, options) in enumerate(fields):
                base = value_for(key, label, dtype, options)
                pattern = (n + i) % 4
                if pattern == 0:  # the AI was unsure; the technician corrected it
                    ai_value, conf, flags = base[:-1] + "?", 0.42, ["low_confidence"]
                    verdict = ("corrected", base, None)
                elif pattern == 3 and not required:  # not readable on the plate
                    ai_value, conf, flags = None, None, ["no_confidence"]
                    verdict = ("unreadable", None, "label_worn")
                else:  # read well and kept
                    ai_value, conf, flags = base, 0.97, []
                    verdict = ("accepted", base, None)
                ai[fid] = one(
                    "INSERT INTO ai_field_value (tenant_id, attempt_id, field_definition_id, value,"
                    " confidence, flag_reasons) VALUES (%s,%s,%s,%s,%s,%s) RETURNING id",
                    (tenant, attempt, fid, ai_value, conf, flags),
                )[0]
                verdicts.append((fid, key, verdict))
                if verdict[1] is not None:
                    values[key] = verdict[1]
            revision = one(
                "INSERT INTO revision (tenant_id, scan_id, revision_no, origin, values_json,"
                " empty_required_fields, submitted_by, submitted_at)"
                " VALUES (%s,%s,1,'technician_review',%s::jsonb,'{}',%s,%s) RETURNING id",
                (tenant, scan_id, json.dumps(values), tech_id, submitted),
            )[0]
            for fid, key, (state, value, reason) in verdicts:
                cur.execute(
                    "INSERT INTO revision_field (tenant_id, revision_id, ai_field_value_id, field_key,"
                    " value, verification_state, unreadable_reason) VALUES (%s,%s,%s,%s,%s,%s,%s)",
                    (tenant, revision, ai[fid], key, value, state, reason),
                )
            added.append((record_no, type_name, tech_name, hours))

        waiting = one(
            "SELECT count(*) FROM scan WHERE bu_id = %s AND review_status = 'waiting_for_approval'",
            (bu,),
        )[0]

    for record_no, type_name, tech_name, hours in added:
        age = f"{hours / 24:.0f} days" if hours >= 48 else f"{hours:g} h"
        print(f"added {record_no}  {type_name:<16} by {tech_name:<11} waiting {age}")
    print(f"{unit_name}: {waiting} scans now waiting for approval")


if __name__ == "__main__":
    main()
