<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true; section>
    <#if section = "header">
        ${msg("pixorexSignInTitle")}
    <#elseif section = "form">
        <form id="px-identifier-form" class="px-form" action="${url.loginAction}" method="post" novalidate
              onsubmit="this.querySelector('button').disabled = true; return true;">
            <label for="identifier" class="px-label">${msg("pixorexIdentifierLabelEmail")}</label>
            <input id="identifier" name="identifier" class="px-input"
                   type="email"
                   inputmode="email"
                   autocomplete="email"
                   autocapitalize="none" spellcheck="false"
                   value="${pxIdentifier}" autofocus required
                   aria-invalid="${(message?has_content && message.type == 'error')?c}">
            <button class="px-button" type="submit">${msg("pixorexContinue")}</button>
        </form>
    </#if>
</@layout.registrationLayout>
