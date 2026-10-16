package com.amzur.pixorex.keycloak.sms;

import org.keycloak.provider.Provider;
import org.keycloak.provider.ProviderFactory;
import org.keycloak.provider.Spi;

/** SPI {@code pixorex-sms}. Pick the provider with {@code KC_SPI_PIXOREX_SMS__PROVIDER} (mailpit, log or amzur). */
public class SmsSpi implements Spi {

    public static final String NAME = "pixorex-sms";

    @Override
    public boolean isInternal() {
        return false;
    }

    @Override
    public String getName() {
        return NAME;
    }

    @Override
    public Class<? extends Provider> getProviderClass() {
        return SmsSender.class;
    }

    @Override
    @SuppressWarnings("rawtypes")
    public Class<? extends ProviderFactory> getProviderFactoryClass() {
        return SmsSenderFactory.class;
    }
}
