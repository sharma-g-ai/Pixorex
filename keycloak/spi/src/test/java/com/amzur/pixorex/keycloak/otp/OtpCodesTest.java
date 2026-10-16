package com.amzur.pixorex.keycloak.otp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.security.SecureRandom;

import org.junit.jupiter.api.Test;

class OtpCodesTest {

    private final SecureRandom random = new SecureRandom();

    @Test
    void givenTheGenerator_whenAskedForSixDigits_thenAlwaysReturnsSixDigits() {
        for (int i = 0; i < 1000; i++) {
            String code = OtpCodes.generate(random, 6);
            assertEquals(6, code.length());
            assertTrue(code.chars().allMatch(Character::isDigit));
        }
    }

    @Test
    void givenManyCodes_whenCountingDigits_thenEveryDigitAppearsRoughlyEqually() {
        int[] counts = new int[10];
        int samples = 20000;
        for (int i = 0; i < samples; i++) {
            for (char c : OtpCodes.generate(random, 6).toCharArray()) {
                counts[c - '0']++;
            }
        }
        double expected = samples * 6 / 10.0;
        for (int count : counts) {
            assertTrue(Math.abs(count - expected) < expected * 0.05, "digit frequency off: " + count);
        }
    }

    @Test
    void givenAStoredHash_whenTheRightCodeIsEntered_thenItMatches() {
        String salt = OtpCodes.newSalt(random);
        String hash = OtpCodes.hash("482913", salt);
        assertTrue(OtpCodes.matches("482913", salt, hash));
    }

    @Test
    void givenAStoredHash_whenAWrongCodeOrSaltIsUsed_thenItDoesNotMatch() {
        String salt = OtpCodes.newSalt(random);
        String hash = OtpCodes.hash("482913", salt);
        assertFalse(OtpCodes.matches("482914", salt, hash));
        assertFalse(OtpCodes.matches("482913", OtpCodes.newSalt(random), hash));
        assertFalse(OtpCodes.matches(null, salt, hash));
        assertFalse(OtpCodes.matches("482913", salt, null));
    }

    @Test
    void givenTheSameCode_whenHashedWithTwoSalts_thenTheHashesDiffer() {
        assertNotEquals(OtpCodes.hash("123456", OtpCodes.newSalt(random)), OtpCodes.hash("123456", OtpCodes.newSalt(random)));
    }

    @Test
    void givenPastedInput_whenNormalized_thenSpacesAndDashesAreIgnoredAndBadInputIsRejected() {
        assertEquals("482913", OtpCodes.normalizeEntered(" 482 913 ", 6));
        assertEquals("482913", OtpCodes.normalizeEntered("482-913", 6));
        assertNull(OtpCodes.normalizeEntered("48291", 6));
        assertNull(OtpCodes.normalizeEntered("48291a", 6));
        assertNull(OtpCodes.normalizeEntered(null, 6));
    }
}
