package com.amzur.pixorex.keycloak.sms;

import org.keycloak.Config;
import org.keycloak.email.EmailException;
import org.keycloak.email.EmailSenderProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;

/**
 * LOCAL ONLY. Delivers each SMS as an email to {@code sms+<digits>@<domain>} through the realm SMTP server (Mailpit),
 * so codes can be read at http://localhost:8025 without a phone.
 */
public class MailpitSmsSenderFactory implements SmsSenderFactory {

    public static final String PROVIDER_ID = "mailpit";

    private String domain = "pixorex.local";

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public void init(Config.Scope config) {
        domain = config.get("domain", domain);
    }

    @Override
    public SmsSender create(KeycloakSession session) {
        return (phoneNumber, message) -> {
            RealmModel realm = session.getContext().getRealm();
            String address = "sms+" + phoneNumber.replaceAll("\\D", "") + "@" + domain;
            try {
                session.getProvider(EmailSenderProvider.class)
                        .send(realm.getSmtpConfig(), address, "SMS to " + phoneNumber, message, null);
            } catch (EmailException e) {
                throw new SmsException("Mailpit SMS delivery failed", e);
            }
        };
    }
}
