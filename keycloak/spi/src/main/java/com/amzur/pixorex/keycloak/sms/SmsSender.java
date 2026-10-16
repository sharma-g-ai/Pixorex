package com.amzur.pixorex.keycloak.sms;

import org.keycloak.provider.Provider;

public interface SmsSender extends Provider {

    /**
     * @param phoneNumber E.164 destination
     * @param message     full SMS text; implementations must never log it, because it contains the code
     * @throws SmsException when the message was not accepted for delivery
     */
    void send(String phoneNumber, String message);

    @Override
    default void close() {
    }
}
