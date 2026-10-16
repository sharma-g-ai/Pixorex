package com.amzur.pixorex.keycloak.otp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.Test;

import com.amzur.pixorex.keycloak.otp.Identifiers.Identifier;
import com.amzur.pixorex.keycloak.otp.Identifiers.Type;

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
    void givenTheWebClient_whenChannelsAreOffered_thenOnlyEmailIsOffered() {
        assertEquals(List.of(Channel.EMAIL), ChannelRules.offered(false, "+15550100001", true));
    }

    @Test
    void givenAnActiveTechnicianOnMobile_whenChannelsAreOffered_thenSmsAndEmailAreOffered() {
        assertEquals(List.of(Channel.SMS, Channel.EMAIL), ChannelRules.offered(true, "+15550100001", true));
    }

    @Test
    void givenAnInvitedTechnicianOnMobile_whenChannelsAreOffered_thenOnlySmsToThePendingNumber() {
        assertEquals(List.of(Channel.SMS), ChannelRules.offered(true, "+15550100002", false));
    }

    @Test
    void givenAMobileUserWithoutPhone_whenChannelsAreOffered_thenEmailIsTheOnlyOption() {
        assertEquals(List.of(Channel.EMAIL), ChannelRules.offered(true, null, false));
    }

    @Test
    void givenAnUnknownIdentifier_whenTheChannelIsPicked_thenItMirrorsWhatWasTyped() {
        assertEquals(Channel.SMS, ChannelRules.forUnknownUser(true, Type.PHONE));
        assertEquals(Channel.EMAIL, ChannelRules.forUnknownUser(true, Type.EMAIL));
        assertEquals(Channel.EMAIL, ChannelRules.forUnknownUser(false, Type.PHONE));
    }

    @Test
    void givenTypedIdentifiers_whenParsed_thenEmailsAreLowercasedAndPhonesBecomeE164() {
        assertEquals(Optional.of(new Identifier(Type.EMAIL, "ea@demo.local")), Identifiers.parse("  EA@Demo.Local ", false));
        assertEquals(Optional.of(new Identifier(Type.PHONE, "+15550100001")), Identifiers.parse("+1 (555) 010-0001", true));
        assertEquals(Optional.of(new Identifier(Type.PHONE, "+15550100001")), Identifiers.parse("0015550100001", true));
    }

    @Test
    void givenBadIdentifiers_whenParsed_thenTheyAreRejected() {
        assertTrue(Identifiers.parse("+15550100001", false).isEmpty(), "web accepts email only");
        assertTrue(Identifiers.parse("5550100001", true).isEmpty(), "phone needs a country code");
        assertTrue(Identifiers.parse("not-an-email@", true).isEmpty());
        assertTrue(Identifiers.parse("", true).isEmpty());
        assertTrue(Identifiers.parse(null, true).isEmpty());
    }

    @Test
    void givenDestinations_whenMasked_thenOnlyAHintIsShown() {
        assertEquals("r\u2022\u2022\u2022\u2022@example.com", Masking.email("ravi@example.com"));
        assertEquals("\u2022\u2022\u2022\u2022 4821", Masking.phone("+15550104821"));
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
        String phone = Throttle.destinationSubject("+15550100001");
        for (int i = 0; i < 5; i++) {
            assertTrue(throttle.allowed(now, user, phone));
            throttle.record(now, user, phone);
        }
        assertFalse(throttle.allowed(now, user, phone));
        assertFalse(throttle.allowed(now, Throttle.userSubject("other-account-same-phone"), phone), "limit applies per destination");
        assertTrue(throttle.allowed(now + 900, user, phone), "next window starts fresh");
        assertEquals(890, throttle.secondsUntilReset(now));
    }
}
