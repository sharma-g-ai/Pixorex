package com.amzur.pixorex.keycloak.auth;

import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import jakarta.ws.rs.core.Response;

import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.common.util.Time;
import org.keycloak.models.AuthenticatorConfigModel;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserLoginFailureModel;
import org.keycloak.models.UserModel;

final class FlowSupport {

    static final String PHONE_NUMBER = "phone_number";
    static final String PHONE_VERIFIED = "phone_verified";

    static final String MESSAGE_TEMPLATE = "pixorex-message.ftl";

    private FlowSupport() {
    }

    static Map<String, String> config(AuthenticationFlowContext context) {
        AuthenticatorConfigModel model = context.getAuthenticatorConfig();
        return model == null || model.getConfig() == null ? Map.of() : model.getConfig();
    }

    static Set<String> csv(Map<String, String> config, String key, String defaultValue) {
        String value = config.getOrDefault(key, defaultValue);
        if (value == null || value.isBlank()) {
            value = defaultValue;
        }
        return Arrays.stream(value.split(",")).map(String::trim).filter(s -> !s.isEmpty()).collect(Collectors.toSet());
    }

    static String clientId(AuthenticationFlowContext context) {
        return context.getAuthenticationSession().getClient().getClientId();
    }

    static boolean phoneVerified(UserModel user) {
        return "true".equals(user.getFirstAttribute(PHONE_VERIFIED));
    }

    /** Full-page message (denied, locked) with a "start over" link. Uses challenge, never failure, so nothing is counted. */
    static Response messagePage(AuthenticationFlowContext context, String titleKey, String messageKey, Object... params) {
        return context.form()
                .setAttribute("pxTitle", titleKey)
                .setError(messageKey, params)
                .createForm(MESSAGE_TEMPLATE);
    }

    static Response lockedPage(AuthenticationFlowContext context, int minutesLeft) {
        return messagePage(context, "pixorexLockedTitle", "pixorexLocked", minutesLeft);
    }

    /** Minutes until brute-force detection lets this user try again (rounded up, at least 1). */
    static int lockMinutesLeft(AuthenticationFlowContext context, UserModel user) {
        RealmModel realm = context.getRealm();
        UserLoginFailureModel failure = context.getSession().loginFailures().getUserLoginFailure(realm, user.getId());
        int seconds = failure == null ? 0 : failure.getFailedLoginNotBefore() - Time.currentTime();
        if (seconds <= 0) {
            seconds = Math.min(realm.getWaitIncrementSeconds(), realm.getMaxFailureWaitSeconds());
        }
        return Math.max(1, (seconds + 59) / 60);
    }

    /** Failures that brute-force detection still counts (it forgets them after the failure reset time). */
    static int countedFailures(AuthenticationFlowContext context, UserModel user) {
        RealmModel realm = context.getRealm();
        UserLoginFailureModel failure = context.getSession().loginFailures().getUserLoginFailure(realm, user.getId());
        if (failure == null) {
            return 0;
        }
        long sinceLastMillis = Time.currentTimeMillis() - failure.getLastFailure();
        return sinceLastMillis > realm.getMaxDeltaTimeSeconds() * 1000L ? 0 : failure.getNumFailures();
    }
}
