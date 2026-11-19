package com.amzur.pixorex.keycloak.auth;

import java.security.SecureRandom;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;

import org.jboss.logging.Logger;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.AuthenticatorUtil;
import org.keycloak.authentication.Authenticator;
import org.keycloak.common.util.Time;
import org.keycloak.email.EmailException;
import org.keycloak.email.EmailTemplateProvider;
import org.keycloak.events.Errors;
import org.keycloak.forms.login.LoginFormsProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.credential.OTPCredentialModel;
import org.keycloak.sessions.AuthenticationSessionModel;

import com.amzur.pixorex.keycloak.otp.Masking;
import com.amzur.pixorex.keycloak.otp.OtpCodes;
import com.amzur.pixorex.keycloak.otp.OtpSettings;
import com.amzur.pixorex.keycloak.otp.SingleUseCounterStore;
import com.amzur.pixorex.keycloak.otp.Throttle;

public class PixorexOtpAuthenticator implements Authenticator {

    static final String TEMPLATE = "pixorex-code.ftl";
    static final String EMAIL_TEMPLATE = "pixorex-code.ftl";
    static final String CODE_FIELD = "code";
    static final String RESEND_FIELD = "resend";

    private static final Logger LOG = Logger.getLogger(PixorexOtpAuthenticator.class);
    private static final SecureRandom RANDOM = new SecureRandom();

    @Override
    public void authenticate(AuthenticationFlowContext context) {
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        boolean liveCode = authSession.getAuthNote(AuthNotes.OTP_HASH) != null
                && Time.currentTime() <= AuthNotes.longNote(authSession, AuthNotes.OTP_EXPIRES_AT);
        boolean ghostShown = context.getUser() == null && authSession.getAuthNote(AuthNotes.OTP_SENT_AT) != null;
        if (liveCode || ghostShown) {
            // A page refresh re-enters the step; only the Resend button may send another code.
            context.challenge(codeForm(context, OtpSettings.from(FlowSupport.config(context))).createForm(TEMPLATE));
            return;
        }
        issueCode(context);
    }

    @Override
    public void action(AuthenticationFlowContext context) {
        OtpSettings settings = OtpSettings.from(FlowSupport.config(context));
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        MultivaluedMap<String, String> form = context.getHttpRequest().getDecodedFormParameters();

        if (form.containsKey(RESEND_FIELD)) {
            long wait = resendWait(authSession, settings);
            if (wait > 0) {
                context.challenge(codeForm(context, settings).setError("pixorexResendWait", wait).createForm(TEMPLATE));
                return;
            }
            issueCode(context);
            return;
        }

        UserModel user = context.getUser();
        if (user == null) {
            // Unknown identifier: always "wrong", never counted, because there is no account to count against.
            context.challenge(codeForm(context, settings).setError("pixorexCodeInvalid").createForm(TEMPLATE));
            return;
        }
        if (PixorexLockCheckAuthenticator.isLocked(context, user)) {
            AuthNotes.clearCode(authSession);
            context.challenge(FlowSupport.lockedPage(context, FlowSupport.lockMinutesLeft(context, user)));
            return;
        }

        String entered = OtpCodes.normalizeEntered(form.getFirst(CODE_FIELD), settings.codeLength());
        String hash = authSession.getAuthNote(AuthNotes.OTP_HASH);
        if (hash == null || Time.currentTime() > AuthNotes.longNote(authSession, AuthNotes.OTP_EXPIRES_AT)) {
            wrongCode(context, user, settings, "pixorexCodeExpired", Errors.EXPIRED_CODE);
            return;
        }
        if (entered == null || !OtpCodes.matches(entered, authSession.getAuthNote(AuthNotes.OTP_SALT), hash)) {
            wrongCode(context, user, settings, "pixorexCodeInvalid", Errors.INVALID_USER_CREDENTIALS);
            return;
        }

        AuthNotes.clearAll(authSession);
        // Brute-force detection only resets the failure count when an otp/password credential was used.
        AuthenticatorUtil.addAuthCredential(authSession, OTPCredentialModel.TYPE);
        boolean activated = activate(user);
        context.getEvent().detail("otp_channel", "email");
        if (activated) {
            context.getEvent().detail("activation", "true");
        }
        context.success();
    }

    private void issueCode(AuthenticationFlowContext context) {
        OtpSettings settings = OtpSettings.from(FlowSupport.config(context));
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        long now = Time.currentTime();
        UserModel user = context.getUser();

        if (user == null) {
            authSession.setAuthNote(AuthNotes.OTP_SENT_AT, String.valueOf(now));
            context.challenge(codeForm(context, settings).createForm(TEMPLATE));
            return;
        }

        String destination = user.getEmail();
        if (destination == null || destination.isBlank()) {
            context.challenge(FlowSupport.messagePage(context, "pixorexErrorTitle", "pixorexNoDestination"));
            return;
        }

        Throttle throttle = new Throttle(new SingleUseCounterStore(context.getSession().singleUseObjects()),
                settings.maxSends(), settings.sendWindowSeconds());
        String[] subjects = { Throttle.userSubject(user.getId()), Throttle.destinationSubject(destination) };
        if (!throttle.allowed(now, subjects)) {
            long minutes = Math.max(1, (throttle.secondsUntilReset(now) + 59) / 60);
            context.getEvent().clone().user(user).detail("reason", "code_send_limit").error("pixorex_code_rate_limited");
            context.challenge(codeForm(context, settings).setError("pixorexTooManyCodes", minutes).createForm(TEMPLATE));
            return;
        }

        String code = OtpCodes.generate(RANDOM, settings.codeLength());
        try {
            send(context, user, code, settings);
        } catch (EmailException e) {
            LOG.warnf(e, "Could not send a code to %s: %s", Masking.email(destination), e.getMessage());
            context.challenge(codeForm(context, settings).setError("pixorexSendFailed").createForm(TEMPLATE));
            return;
        }
        throttle.record(now, subjects);

        String salt = OtpCodes.newSalt(RANDOM);
        authSession.setAuthNote(AuthNotes.OTP_SALT, salt);
        authSession.setAuthNote(AuthNotes.OTP_HASH, OtpCodes.hash(code, salt));
        authSession.setAuthNote(AuthNotes.OTP_EXPIRES_AT, String.valueOf(now + settings.ttlSeconds()));
        authSession.setAuthNote(AuthNotes.OTP_SENT_AT, String.valueOf(now));
        context.challenge(codeForm(context, settings).createForm(TEMPLATE));
    }

    private void wrongCode(AuthenticationFlowContext context, UserModel user, OtpSettings settings, String messageKey, String eventError) {
        RealmModel realm = context.getRealm();
        boolean locksNow = realm.isBruteForceProtected()
                && FlowSupport.countedFailures(context, user) + 1 >= realm.getFailureFactor();
        Response page;
        if (locksNow) {
            AuthNotes.clearCode(context.getAuthenticationSession());
            page = FlowSupport.lockedPage(context, Math.max(1, Math.min(realm.getWaitIncrementSeconds(), realm.getMaxFailureWaitSeconds()) / 60));
        } else {
            page = codeForm(context, settings).setError(messageKey).createForm(TEMPLATE);
        }
        context.getEvent().user(user).error(eventError);
        context.failureChallenge(AuthenticationFlowError.INVALID_CREDENTIALS, page);
    }

    private static void send(AuthenticationFlowContext context, UserModel user, String code, OtpSettings settings)
            throws EmailException {
        KeycloakSession session = context.getSession();
        // Keycloak adds locale and theme entries to this map, so it must be mutable.
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("code", code);
        attributes.put("ttlMinutes", settings.ttlMinutes());
        session.getProvider(EmailTemplateProvider.class)
                .setRealm(context.getRealm())
                .setUser(user)
                .setAuthenticationSession(context.getAuthenticationSession())
                .send("pixorexCodeSubject", List.of(), EMAIL_TEMPLATE, attributes);
    }

    /** The first correct email code verifies the email, which completes activation (docs/keycloak.md §6.4, O-12). */
    static boolean activate(UserModel user) {
        if (!user.isEmailVerified()) {
            user.setEmailVerified(true);
            return true;
        }
        return false;
    }

    private static LoginFormsProvider codeForm(AuthenticationFlowContext context, OtpSettings settings) {
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        UserModel user = context.getUser();
        String destination = user == null ? authSession.getAuthNote(AuthNotes.IDENTIFIER) : user.getEmail();
        return context.form()
                .setAttribute("pxDestination", Masking.email(destination))
                .setAttribute("pxCodeLength", settings.codeLength())
                .setAttribute("pxTtlMinutes", settings.ttlMinutes())
                .setAttribute("pxResendIn", resendWait(authSession, settings));
    }

    private static long resendWait(AuthenticationSessionModel authSession, OtpSettings settings) {
        long sentAt = AuthNotes.longNote(authSession, AuthNotes.OTP_SENT_AT);
        return sentAt == 0 ? 0 : Math.max(0, sentAt + settings.resendCooldownSeconds() - Time.currentTime());
    }

    @Override
    public boolean requiresUser() {
        return false;
    }

    @Override
    public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) {
        return true;
    }

    @Override
    public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) {
    }

    @Override
    public void close() {
    }
}
