package com.amzur.pixorex.keycloak.sms;

import org.jboss.logging.Logger;
import org.keycloak.models.KeycloakSession;

import com.amzur.pixorex.keycloak.otp.Masking;

/** Logs that an SMS would have been sent, with the number masked and the text (and so the code) left out. */
public class LogSmsSenderFactory implements SmsSenderFactory {

    public static final String PROVIDER_ID = "log";

    private static final Logger LOG = Logger.getLogger(LogSmsSenderFactory.class);

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public SmsSender create(KeycloakSession session) {
        return (phoneNumber, message) ->
                LOG.infof("SMS to %s (%d characters, content redacted)", Masking.phone(phoneNumber), message.length());
    }
}
