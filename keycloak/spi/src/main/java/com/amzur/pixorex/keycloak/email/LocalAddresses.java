package com.amzur.pixorex.keycloak.email;

/**
 * Synthetic / local-only addresses used in development. These must never go through a real
 * provider (SendGrid rejects {@code .local}); they always land in Mailpit.
 */
public final class LocalAddresses {

    private LocalAddresses() {
    }

    /** True for {@code *@demo.local}, {@code sms+*@pixorex.local}, and any other {@code *.local}. */
    public static boolean isSynthetic(String address) {
        if (address == null) {
            return false;
        }
        String trimmed = address.trim();
        int at = trimmed.lastIndexOf('@');
        if (at < 0 || at == trimmed.length() - 1) {
            return false;
        }
        return trimmed.substring(at + 1).toLowerCase().endsWith(".local");
    }
}
