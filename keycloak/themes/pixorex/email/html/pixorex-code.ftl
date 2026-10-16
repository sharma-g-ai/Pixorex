<#import "template.ftl" as layout>
<@layout.emailLayout>
<p>${msg("pixorexCodeIntro")}</p>
<p style="font-size:28px;font-weight:700;letter-spacing:6px;font-family:Consolas,Menlo,monospace;margin:16px 0;">${code}</p>
<p>${msg("pixorexCodeExpiry", ttlMinutes)}</p>
<p style="color:#5b6470;">${msg("pixorexCodeIgnore")}</p>
</@layout.emailLayout>
