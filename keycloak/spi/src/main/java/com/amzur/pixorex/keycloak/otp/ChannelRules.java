package com.amzur.pixorex.keycloak.otp;

import java.util.List;

/**
 * Channel rules from docs/keycloak.md §4.2. The client decides whether SMS is possible at all, so a person with both
 * admin and technician roles still gets email only on the web dashboard.
 */
public final class ChannelRules {

    private ChannelRules() {
    }

    public static List<Channel> offered(boolean smsAllowedForClient, String phoneNumber, boolean phoneVerified) {
        boolean hasPhone = phoneNumber != null && !phoneNumber.isBlank();
        if (smsAllowedForClient && hasPhone) {
            // Invited technician: the code to the pending number is what verifies it and activates the account.
            return phoneVerified ? List.of(Channel.SMS, Channel.EMAIL) : List.of(Channel.SMS);
        }
        return List.of(Channel.EMAIL);
    }

    /** Unknown identifiers follow the shape of a real sign-in so the screens never reveal whether an account exists. */
    public static Channel forUnknownUser(boolean smsAllowedForClient, Identifiers.Type identifierType) {
        return smsAllowedForClient && identifierType == Identifiers.Type.PHONE ? Channel.SMS : Channel.EMAIL;
    }
}
