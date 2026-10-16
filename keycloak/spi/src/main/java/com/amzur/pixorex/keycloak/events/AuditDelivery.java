package com.amzur.pixorex.keycloak.events;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.HexFormat;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import org.jboss.logging.Logger;

import com.amzur.pixorex.keycloak.otp.OtpCodes;

/**
 * Bounded, best-effort delivery off the request thread. Lost events (queue full, Keycloak restart) are recovered by the
 * API's reconciliation job, which reads Keycloak's stored events (docs/keycloak.md §8.4).
 */
public final class AuditDelivery {

    public static final String SIGNATURE_HEADER = "X-Pixorex-Signature";
    public static final String EVENT_ID_HEADER = "X-Pixorex-Event-Id";

    private static final Logger LOG = Logger.getLogger(AuditDelivery.class);

    private final URI endpoint;
    private final byte[] secret;
    private final int maxAttempts;
    private final int maxQueued;
    private final Duration timeout;
    private final HttpClient client;
    private final ScheduledThreadPoolExecutor executor;
    private final AtomicInteger queued = new AtomicInteger();

    public AuditDelivery(String endpoint, String secret, int maxAttempts, int maxQueued, Duration timeout) {
        this.endpoint = URI.create(endpoint);
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
        this.maxAttempts = maxAttempts;
        this.maxQueued = maxQueued;
        this.timeout = timeout;
        this.client = HttpClient.newBuilder().connectTimeout(timeout).followRedirects(HttpClient.Redirect.NEVER).build();
        this.executor = new ScheduledThreadPoolExecutor(1, runnable -> {
            Thread thread = new Thread(runnable, "pixorex-audit");
            thread.setDaemon(true);
            return thread;
        });
        this.executor.setRemoveOnCancelPolicy(true);
    }

    public static String signature(byte[] secret, String body) {
        return "sha256=" + HexFormat.of().formatHex(OtpCodes.hmac(secret, body));
    }

    public void submit(String eventId, String body) {
        if (queued.incrementAndGet() > maxQueued) {
            queued.decrementAndGet();
            LOG.warnf("Audit queue full, dropping event %s (reconciliation will pick it up)", eventId);
            return;
        }
        executor.execute(() -> attempt(eventId, body, 1));
    }

    private void attempt(String eventId, String body, int attempt) {
        boolean done = false;
        try {
            HttpRequest request = HttpRequest.newBuilder(endpoint)
                    .timeout(timeout)
                    .header("Content-Type", "application/json")
                    .header(EVENT_ID_HEADER, eventId)
                    .header(SIGNATURE_HEADER, signature(secret, body))
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            int status = client.send(request, HttpResponse.BodyHandlers.discarding()).statusCode();
            done = status / 100 == 2;
            if (!done) {
                LOG.debugf("Audit event %s attempt %d got HTTP %d", eventId, attempt, status);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Exception e) {
            LOG.debugf("Audit event %s attempt %d failed: %s", eventId, attempt, e.toString());
        }
        if (done) {
            queued.decrementAndGet();
        } else if (attempt < maxAttempts && !executor.isShutdown()) {
            executor.schedule(() -> attempt(eventId, body, attempt + 1), 1L << (attempt - 1), TimeUnit.SECONDS);
        } else {
            queued.decrementAndGet();
            LOG.warnf("Gave up delivering audit event %s after %d attempts (reconciliation will pick it up)", eventId, attempt);
        }
    }

    public void shutdown() {
        executor.shutdown();
    }
}
