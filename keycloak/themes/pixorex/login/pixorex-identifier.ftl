<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true; section>
    <#if section = "header">
        ${msg("pixorexSignInTitle")}
    <#elseif section = "form">
        <form id="px-identifier-form" class="px-form" action="${url.loginAction}" method="post" novalidate
              onsubmit="this.querySelector('button').disabled = true; return true;">
            <label for="identifier" class="px-label">
                <#if pxAllowPhone>${msg("pixorexIdentifierLabelMobile")}<#else>${msg("pixorexIdentifierLabelEmail")}</#if>
            </label>
            <input id="identifier" name="identifier" class="px-input"
                   type="<#if pxAllowPhone>text<#else>email</#if>"
                   inputmode="email"
                   autocomplete="<#if pxAllowPhone>username<#else>email</#if>"
                   autocapitalize="none" spellcheck="false"
                   value="${pxIdentifier}" autofocus required
                   aria-invalid="${(message?has_content && message.type == 'error')?c}"
                   <#if pxAllowPhone>aria-describedby="px-identifier-hint"</#if>>
            <#if pxAllowPhone>
                <p id="px-identifier-hint" class="px-hint">${msg("pixorexIdentifierHintMobile")}</p>
            </#if>
            <button class="px-button" type="submit">${msg("pixorexContinue")}</button>
        </form>
    </#if>
</@layout.registrationLayout>
