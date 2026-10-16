package com.amzur.pixorex.keycloak.events;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import org.keycloak.events.Event;
import org.keycloak.events.EventType;

/** JSON body for POST /internal/keycloak-events. Never carries codes, tokens or the raw identifier the user typed. */
public final class AuditPayload {

    public static final Set<EventType> FORWARDED = Set.of(
            EventType.LOGIN, EventType.LOGIN_ERROR, EventType.LOGOUT,
            EventType.CODE_TO_TOKEN_ERROR, EventType.REFRESH_TOKEN_ERROR);

    private static final Set<String> DROPPED_DETAILS = Set.of("username", "code_id", "token_id", "refresh_token_id");

    private AuditPayload() {
    }

    public static Map<String, Object> build(Event event, String appUserId, String tenantId) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("id", event.getId());
        body.put("type", event.getType().name());
        body.put("time", event.getTime());
        body.put("realm", event.getRealmName());
        body.put("client_id", event.getClientId());
        body.put("user_id", event.getUserId());
        body.put("app_user_id", appUserId);
        body.put("tenant_id", tenantId);
        body.put("session_id", event.getSessionId());
        body.put("ip_address", event.getIpAddress());
        body.put("error", event.getError());
        Map<String, String> details = new TreeMap<>();
        if (event.getDetails() != null) {
            event.getDetails().forEach((key, value) -> {
                if (!DROPPED_DETAILS.contains(key)) {
                    details.put(key, value);
                }
            });
        }
        body.put("details", details);
        return body;
    }
}
