package com.amzur.pixorex.keycloak.otp;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * One-time codes are never stored in clear: the auth session keeps an HMAC of the code keyed by a random per-code salt.
 */
public final class OtpCodes {

    private static final String HMAC = "HmacSHA256";

    private OtpCodes() {
    }

    public static String generate(SecureRandom random, int length) {
        StringBuilder code = new StringBuilder(length);
        for (int i = 0; i < length; i++) {
            code.append(random.nextInt(10));
        }
        return code.toString();
    }

    public static String newSalt(SecureRandom random) {
        byte[] salt = new byte[16];
        random.nextBytes(salt);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(salt);
    }

    public static String hash(String code, String salt) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(hmac(salt.getBytes(StandardCharsets.UTF_8), code));
    }

    public static boolean matches(String enteredCode, String salt, String expectedHash) {
        if (enteredCode == null || salt == null || expectedHash == null) {
            return false;
        }
        byte[] actual = hash(enteredCode, salt).getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(actual, expectedHash.getBytes(StandardCharsets.UTF_8));
    }

    /** Strips spaces and dashes users paste from SMS apps; returns null unless exactly {@code length} digits remain. */
    public static String normalizeEntered(String raw, int length) {
        if (raw == null) {
            return null;
        }
        String digits = raw.replaceAll("[\\s-]", "");
        return digits.length() == length && digits.chars().allMatch(Character::isDigit) ? digits : null;
    }

    public static String sha256Hex(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    public static byte[] hmac(byte[] key, String data) {
        try {
            Mac mac = Mac.getInstance(HMAC);
            mac.init(new SecretKeySpec(key, HMAC));
            return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }
}
