package com.amzur.pixorex.keycloak.otp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.Test;

class PolicyTest {

    @Test
    void givenNoExecutionConfig_whenSettingsAreRead_thenTheDocumentedDefaultsApply() {
        assertEquals(new OtpSettings(6, 300, 60, 5, 900), OtpSettings.from(null));
        assertEquals(5, OtpSettings.DEFAULTS.ttlMinutes());
    }

    @Test
    void givenOutOfRangeConfig_whenSettingsAreRead_thenUnsafeValuesFallBackToDefaults() {
        OtpSettings settings = OtpSettings.from(Map.of("codeLength", "4", "ttlSeconds", "30", "maxSends", "abc"));
        assertEquals(6, settings.codeLength());
        assertEquals(30, settings.ttlSeconds());
        assertEquals(5, settings.maxSends());
    }

    @Test
    void givenTypedEmails_whenParsed_thenTheyAreTrimmedAndLowercased() {
        assertEquals(Optional.of("ea@demo.local"), Identifiers.email("  EA@Demo.Local "));
    }

    @Test
    void givenAnythingButAnEmail_whenParsed_thenItIsRejected() {
        // Sign-in is by email only, on the web and the mobile app (phone sign-in removed, 19 Nov 2026).
        assertTrue(Identifiers.email("+15550100001").isEmpty(), "a mobile number is not an identifier");
        assertTrue(Identifiers.email("0015550100001").isEmpty());
        assertTrue(Identifiers.email("not-an-email@").isEmpty());
        assertTrue(Identifiers.email("").isEmpty());
        assertTrue(Identifiers.email(null).isEmpty());
    }

    @Test
    void givenAnEmail_whenMasked_thenOnlyAHintIsShown() {
        assertEquals("r\u2022\u2022\u2022\u2022@example.com", Masking.email("ravi@example.com"));
    }

    @Test
    void givenTheSendLimit_whenFiveCodesWereSent_thenTheSixthIsRefusedUntilTheWindowResets() {
        Map<String, Integer> counters = new HashMap<>();
        Throttle throttle = new Throttle(new Throttle.CounterStore() {
            public int get(String key) {
                return counters.getOrDefault(key, 0);
            }

            public void increment(String key, long lifespanSeconds) {
                counters.merge(key, 1, Integer::sum);
            }
        }, 5, 900);
        long now = 900 * 1000 + 10;
        String user = Throttle.userSubject("u1");
        String inbox = Throttle.destinationSubject("tara@demo.local");
        for (int i = 0; i < 5; i++) {
            assertTrue(throttle.allowed(now, user, inbox));
            throttle.record(now, user, inbox);
        }
        assertFalse(throttle.allowed(now, user, inbox));
        assertFalse(throttle.allowed(now, Throttle.userSubject("other-account-same-inbox"), inbox), "limit applies per destination");
        assertTrue(throttle.allowed(now + 900, user, inbox), "next window starts fresh");
        assertEquals(890, throttle.secondsUntilReset(now));
    }
}
