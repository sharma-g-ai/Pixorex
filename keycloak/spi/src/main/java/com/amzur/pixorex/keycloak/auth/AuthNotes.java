package com.amzur.pixorex.keycloak.auth;

import org.keycloak.sessions.AuthenticationSessionModel;

/** Server-side notes on the authentication session (one browser sign-in attempt). Never sent to the browser. */
final class AuthNotes {

    static final String GHOST = "px.ghost";
    static final String IDENTIFIER = "px.identifier";
    static final String IDENTIFIER_TYPE = "px.identifier.type";
    static final String CHANNEL = "px.channel";
    static final String CHANNELS_OFFERED = "px.channels";

    static final String OTP_HASH = "px.otp.hash";
    static final String OTP_SALT = "px.otp.salt";
    static final String OTP_EXPIRES_AT = "px.otp.expires";
    static final String OTP_SENT_AT = "px.otp.sent";

    private AuthNotes() {
    }

    static boolean isGhost(AuthenticationSessionModel session) {
        return "true".equals(session.getAuthNote(GHOST));
    }

    static void clearCode(AuthenticationSessionModel session) {
        session.removeAuthNote(OTP_HASH);
        session.removeAuthNote(OTP_SALT);
        session.removeAuthNote(OTP_EXPIRES_AT);
    }

    static void clearAll(AuthenticationSessionModel session) {
        clearCode(session);
        session.removeAuthNote(OTP_SENT_AT);
        session.removeAuthNote(GHOST);
        session.removeAuthNote(IDENTIFIER);
        session.removeAuthNote(IDENTIFIER_TYPE);
        session.removeAuthNote(CHANNEL);
        session.removeAuthNote(CHANNELS_OFFERED);
    }

    static long longNote(AuthenticationSessionModel session, String key) {
        String value = session.getAuthNote(key);
        if (value == null) {
            return 0;
        }
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
