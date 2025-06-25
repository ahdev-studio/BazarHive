# Keep rules for Google Play Services Credentials API and smart_auth plugin
-keep class com.google.android.gms.auth.api.credentials.** { *; }
-dontwarn com.google.android.gms.auth.api.credentials.**
-keep class fman.ge.smart_auth.** { *; }
-dontwarn fman.ge.smart_auth.**
