package com.amzur.pixorex.keycloak.events;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.keycloak.events.Event;
import org.keycloak.events.EventType;

class AuditPayloadTest {

    @Test
    void givenALoginEvent_whenBuilt_thenItCarriesTheIdsAndDropsSensitiveDetails() {
        Event event = new Event();
        event.setId("evt-1");
        event.setType(EventType.LOGIN);
        event.setTime(1000L);
        event.setRealmName("pixorex");
        event.setClientId("pixorex-web");
        event.setUserId("kc-user");
        event.setDetails(Map.of("activation", "true", "username", "ea@demo.local", "code_id", "abc"));

        Map<String, Object> body = AuditPayload.build(event, "app-user", "tenant");

        assertEquals("evt-1", body.get("id"));
        assertEquals("LOGIN", body.get("type"));
        assertEquals("app-user", body.get("app_user_id"));
        assertEquals("tenant", body.get("tenant_id"));
        @SuppressWarnings("unchecked")
        Map<String, String> details = (Map<String, String>) body.get("details");
        assertEquals(Map.of("activation", "true"), details);
    }

    @Test
    void givenTheForwardedTypes_whenChecked_thenOnlySignInEventsAreSent() {
        assertTrue(AuditPayload.FORWARDED.contains(EventType.LOGIN_ERROR));
        assertFalse(AuditPayload.FORWARDED.contains(EventType.CODE_TO_TOKEN));
    }

    @Test
    void givenABody_whenSigned_thenTheSignatureIsHexHmacSha256() {
        // RFC 4231 test case 2
        assertEquals("sha256=5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
                AuditDelivery.signature("Jefe".getBytes(StandardCharsets.UTF_8), "what do ya want for nothing?"));
    }
}
