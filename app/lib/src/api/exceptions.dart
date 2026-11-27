/// Typed errors for the NOVA PHOTOS API layer.
///
/// The Immich server does not document its error JSON shape (v3 moved to
/// Zod-structured errors with the correlation id in the `X-Correlation-ID`
/// response header), so every error is parsed defensively: the HTTP status
/// is authoritative, the message is best-effort, and the correlation id is
/// kept for bug reports. Callers must never receive a raw string throw.
library;

import 'dart:convert' show jsonDecode;

/// Base class for every error raised by the API layer.
class ImmichApiException implements Exception {
  const ImmichApiException(this.message, {this.statusCode, this.correlationId});

  /// Human-readable message (never a raw JSON dump).
  final String message;

  /// HTTP status code when the server answered, null on transport failure.
  final int? statusCode;

  /// Value of the `X-Correlation-ID` response header, when present.
  final String? correlationId;

  @override
  String toString() =>
      'ImmichApiException(${statusCode ?? 'no-status'}): $message';
}

/// No network / DNS / TLS failure, or the request timed out.
class ImmichNetworkException extends ImmichApiException {
  const ImmichNetworkException(super.message);
}

/// 401 — the stored token is missing, expired or revoked.
class ImmichUnauthorizedException extends ImmichApiException {
  const ImmichUnauthorizedException(super.message, {super.correlationId})
      : super(statusCode: 401);
}

/// 403 — authenticated, but the credential lacks the required permission
/// (most often an API key missing one of the granular scopes).
class ImmichForbiddenException extends ImmichApiException {
  const ImmichForbiddenException(super.message, {super.correlationId})
      : super(statusCode: 403);
}

/// 404 — unknown id / unknown route.
class ImmichNotFoundException extends ImmichApiException {
  const ImmichNotFoundException(super.message, {super.correlationId})
      : super(statusCode: 404);
}

/// 400 — the request body failed server-side validation.
class ImmichValidationException extends ImmichApiException {
  const ImmichValidationException(super.message, {super.correlationId})
      : super(statusCode: 400);
}

/// 413 — the uploaded file exceeds the server limit.
class ImmichFileTooLargeException extends ImmichApiException {
  const ImmichFileTooLargeException(super.message, {super.correlationId})
      : super(statusCode: 413);
}

/// 5xx — the server faulted.
class ImmichServerException extends ImmichApiException {
  const ImmichServerException(super.message, {super.correlationId})
      : super(statusCode: 500);
}

/// The server answered, but its version is outside NOVA's supported range.
class ImmichVersionException extends ImmichApiException {
  const ImmichVersionException(super.message);
}

/// The server could not be reached at all during endpoint probing
/// (wrong URL, server down, TLS problem). Never disables TLS.
class ImmichUnreachableException extends ImmichApiException {
  const ImmichUnreachableException(super.message);
}

/// Build a typed exception from an HTTP status + raw body.
///
/// Parses defensively: tries `message` (string or list of strings),
/// then `error`, then falls back to the raw body truncated to 300 chars.
ImmichApiException exceptionFromResponse(
  int statusCode,
  String body, {
  String? correlationId,
}) {
  final message = _extractMessage(body, statusCode);
  return switch (statusCode) {
    400 => ImmichValidationException(message, correlationId: correlationId),
    401 => ImmichUnauthorizedException(message, correlationId: correlationId),
    403 => ImmichForbiddenException(message, correlationId: correlationId),
    404 => ImmichNotFoundException(message, correlationId: correlationId),
    413 => ImmichFileTooLargeException(message, correlationId: correlationId),
    >= 500 => ImmichServerException(message, correlationId: correlationId),
    _ => ImmichApiException(message,
        statusCode: statusCode, correlationId: correlationId),
  };
}

String _extractMessage(String body, int statusCode) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return 'Server returned HTTP $statusCode.';
  // Best-effort JSON parse; never throws.
  try {
    final decoded = _tryDecodeJson(trimmed);
    if (decoded is Map<String, Object?>) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        return message.map((e) => e.toString()).join('; ');
      }
      final error = decoded['error'];
      if (error is String && error.isNotEmpty) return error;
    }
  } catch (_) {
    // Fall through to the raw-body fallback.
  }
  return trimmed.length > 300
      ? '${trimmed.substring(0, 300)}…'
      : trimmed;
}

Object? _tryDecodeJson(String source) => jsonDecode(source);
