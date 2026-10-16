package com.amzur.pixorex.keycloak.events;

import org.jboss.logging.Logger;
import org.keycloak.events.Event;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.admin.AdminEvent;
import org.keycloak.models.AbstractKeycloakTransaction;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.util.JsonSerialization;

public class AuditEventListenerProvider implements EventListenerProvider {

    private static final Logger LOG = Logger.getLogger(AuditEventListenerProvider.class);

    private final KeycloakSession session;
    private final AuditDelivery delivery;

    public AuditEventListenerProvider(KeycloakSession session, AuditDelivery delivery) {
        this.session = session;
        this.delivery = delivery;
    }

    @Override
    public void onEvent(Event event) {
        if (delivery == null || event.getType() == null || !AuditPayload.FORWARDED.contains(event.getType())) {
            return;
        }
        try {
            String appUserId = null;
            String tenantId = null;
            if (event.getUserId() != null) {
                RealmModel realm = session.realms().getRealm(event.getRealmId());
                UserModel user = realm == null ? null : session.users().getUserById(realm, event.getUserId());
                if (user != null) {
                    appUserId = user.getFirstAttribute("app_user_id");
                    tenantId = user.getFirstAttribute("tenant_id");
                }
            }
            String body = JsonSerialization.writeValueAsString(AuditPayload.build(event, appUserId, tenantId));
            String eventId = event.getId();
            // Sign-in errors roll the transaction back, and they still have to be audited, so both outcomes deliver.
            session.getTransactionManager().enlistAfterCompletion(new AbstractKeycloakTransaction() {
                @Override
                protected void commitImpl() {
                    delivery.submit(eventId, body);
                }

                @Override
                protected void rollbackImpl() {
                    delivery.submit(eventId, body);
                }
            });
        } catch (Exception e) {
            LOG.warnf("Could not queue audit event %s: %s", event.getId(), e.toString());
        }
    }

    @Override
    public void onEvent(AdminEvent event, boolean includeRepresentation) {
    }

    @Override
    public void close() {
    }
}
