package com.amzur.pixorex.keycloak.auth;

import java.util.List;

import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.credential.OTPCredentialModel;
import org.keycloak.provider.ProviderConfigProperty;

import com.amzur.pixorex.keycloak.otp.OtpSettings;

public class PixorexOtpAuthenticatorFactory extends AbstractPixorexAuthenticatorFactory {

    public static final String PROVIDER_ID = "pixorex-otp";

    /** Brute-force detection only counts failures from the password, otp and recovery-code categories. */
    @Override
    public String getReferenceCategory() {
        return OTPCredentialModel.TYPE;
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayType() {
        return "Pixorex OTP";
    }

    @Override
    public String getHelpText() {
        return "Generates a one-time code, sends it by the chosen channel, verifies it, reports wrong codes to brute-force detection and activates invited accounts.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        OtpSettings d = OtpSettings.DEFAULTS;
        return List.of(
                stringProperty(OtpSettings.CODE_LENGTH, "Code length", "Digits per code (6-8).", String.valueOf(d.codeLength())),
                stringProperty(OtpSettings.TTL_SECONDS, "Code lifetime (seconds)", "How long a code stays valid (30-900).", String.valueOf(d.ttlSeconds())),
                stringProperty(OtpSettings.RESEND_COOLDOWN_SECONDS, "Resend cooldown (seconds)", "Minimum wait between two sends in one sign-in.", String.valueOf(d.resendCooldownSeconds())),
                stringProperty(OtpSettings.MAX_SENDS, "Max sends per window", "Codes per user and per destination in one window.", String.valueOf(d.maxSends())),
                stringProperty(OtpSettings.SEND_WINDOW_SECONDS, "Send window (seconds)", "Length of the send-limit window.", String.valueOf(d.sendWindowSeconds())));
    }

    @Override
    public Authenticator create(KeycloakSession session) {
        return new PixorexOtpAuthenticator();
    }
}
