import 'package:flutter/material.dart';

enum ToolCategory {
  vietnam,
  finance,
  market,
  newsEnvironment,
}

enum ToolAvailability {
  ready,
  partial,
  needsConfiguration,
  unavailable,
}

enum ToolResultFreshness {
  live,
  recent,
  cached,
  staticData,
}

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
    required this.keywords,
    required this.examples,
    this.availability = ToolAvailability.ready,
    this.requiresInternet = true,
    this.supportsVoice = true,
  });

  final String id;
  final String name;
  final String description;
  final ToolCategory category;
  final IconData icon;
  final List<String> keywords;
  final List<String> examples;
  final ToolAvailability availability;
  final bool requiresInternet;
  final bool supportsVoice;
}

class ToolRoute {
  const ToolRoute({
    required this.toolId,
    required this.confidence,
    this.parameters = const <String, String>{},
    this.reason = '',
  });

  final String toolId;
  final double confidence;
  final Map<String, String> parameters;
  final String reason;
}

class ToolResult {
  const ToolResult({
    required this.toolId,
    required this.title,
    required this.summary,
    required this.source,
    required this.timestamp,
    required this.success,
    this.details = const <String, String>{},
    this.latencyMs = 0,
    this.freshness = ToolResultFreshness.live,
    this.errorCode,
    this.userMessage,
    this.sourceUrl,
  });

  final String toolId;
  final String title;
  final String summary;
  final String source;
  final DateTime timestamp;
  final bool success;
  final Map<String, String> details;
  final int latencyMs;
  final ToolResultFreshness freshness;
  final String? errorCode;
  final String? userMessage;
  final Uri? sourceUrl;

  ToolResult copyWith({
    String? summary,
    Map<String, String>? details,
    int? latencyMs,
    ToolResultFreshness? freshness,
  }) {
    return ToolResult(
      toolId: toolId,
      title: title,
      summary: summary ?? this.summary,
      source: source,
      timestamp: timestamp,
      success: success,
      details: details ?? this.details,
      latencyMs: latencyMs ?? this.latencyMs,
      freshness: freshness ?? this.freshness,
      errorCode: errorCode,
      userMessage: userMessage,
      sourceUrl: sourceUrl,
    );
  }
}

extension ToolCategoryLabel on ToolCategory {
  String get label {
    switch (this) {
      case ToolCategory.vietnam:
        return 'Việt Nam';
      case ToolCategory.finance:
        return 'Tài chính';
      case ToolCategory.market:
        return 'Thị trường';
      case ToolCategory.newsEnvironment:
        return 'Tin tức & môi trường';
    }
  }
}

extension ToolAvailabilityLabel on ToolAvailability {
  String get label {
    switch (this) {
      case ToolAvailability.ready:
        return 'Sẵn sàng';
      case ToolAvailability.partial:
        return 'Một phần';
      case ToolAvailability.needsConfiguration:
        return 'Cần cấu hình';
      case ToolAvailability.unavailable:
        return 'Tạm dừng';
    }
  }
}
