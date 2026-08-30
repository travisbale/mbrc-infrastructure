#!/usr/bin/env bash
#
# heimdall's Cloud Run environment, declared once. deploy.sh sets it on a service it is
# creating; set-env.sh updates it on one that is already running. Sourced, not run.
#
# Secrets are not here: they are wired with --set-secrets and are Secret Manager references
# rather than values, so they belong with the deploy that mounts them.

# The SPA origin(s). PUBLIC_URL is the *frontend* base — heimdall builds the password-reset
# and email-verification links users click from it.
PUBLIC_URL="${PUBLIC_URL:-https://manitobarydercup.com}"
CORS_ORIGINS="${CORS_ORIGINS:-https://manitobarydercup.com,https://www.manitobarydercup.com}"

# `^@^` makes @ the delimiter between vars, so CORS_ALLOWED_ORIGINS can contain commas.
# The two JWT keys mount in separate directories on purpose: Cloud Run derives a volume per
# secret and refuses two at the same mount point, so these paths must match --set-secrets.
ENV_VARS="^@^ENVIRONMENT=production@LOG_FORMAT=json@HTTP_ADDRESS=:8080@PUBLIC_URL=${PUBLIC_URL}@TRUSTED_PROXY_MODE=true@CORS_ALLOWED_ORIGINS=${CORS_ORIGINS}@JWT_PRIVATE_KEY_PATH=/secrets/jwt-private/private.pem@JWT_PUBLIC_KEY_PATH=/secrets/jwt-public/public.pem"
