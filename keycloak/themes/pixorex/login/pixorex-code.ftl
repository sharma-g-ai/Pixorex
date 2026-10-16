<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true; section>
    <#if section = "header">
        ${msg("pixorexCodeTitle")}
    <#elseif section = "form">
        <p class="px-lead">
            <#if pxChannel == "sms">${msg("pixorexCodeSentSms", pxDestination, pxTtlMinutes)}<#else>${msg("pixorexCodeSentEmail", pxDestination, pxTtlMinutes)}</#if>
        </p>
        <form id="px-code-form" class="px-form" action="${url.loginAction}" method="post"
              onsubmit="this.querySelector('button').disabled = true; return true;">
            <label for="code" class="px-label">${msg("pixorexCodeLabel", pxCodeLength)}</label>
            <input id="code" name="code" class="px-input px-input-code" type="text"
                   inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]*"
                   maxlength="${pxCodeLength}" autofocus required
                   aria-invalid="${(message?has_content && message.type == 'error')?c}">
            <button class="px-button" type="submit" name="verify" value="1">${msg("pixorexVerify")}</button>
        </form>
        <form id="px-resend-form" class="px-form-inline" action="${url.loginAction}" method="post">
            <button id="px-resend" class="px-link-button" type="submit" name="resend" value="1"
                    data-wait="${pxResendIn?c}" data-label="${msg('pixorexResend')}" data-label-wait="${msg('pixorexResendIn', '#')}"
                    <#if pxResendIn gt 0>disabled</#if>>
                <#if pxResendIn gt 0>${msg("pixorexResendIn", pxResendIn?c)}<#else>${msg("pixorexResend")}</#if>
            </button>
        </form>
        <a class="px-link" href="${url.loginRestartFlowUrl}">${msg("pixorexStartOver")}</a>
        <script>
            (function () {
                var button = document.getElementById("px-resend");
                var wait = parseInt(button.dataset.wait, 10) || 0;
                if (wait <= 0) { return; }
                var timer = setInterval(function () {
                    wait -= 1;
                    if (wait <= 0) {
                        clearInterval(timer);
                        button.disabled = false;
                        button.textContent = button.dataset.label;
                    } else {
                        button.textContent = button.dataset.labelWait.replace("#", wait);
                    }
                }, 1000);
            })();
        </script>
    </#if>
</@layout.registrationLayout>
