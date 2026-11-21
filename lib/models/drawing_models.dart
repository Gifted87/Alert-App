import 'package:flutter/material.dart';

enum DrawingTool {
  none('Cursor', Icons.pan_tool_alt),
  horizontalLine('Horizontal Line', Icons.horizontal_rule),
  trendline('Trendline', Icons.show_chart),
  ray('Ray', Icons.trending_up),
  fibonacci('Fibonacci', Icons.format_line_spacing),
  rectangle('Rectangle', Icons.crop_square),
  verticalLine('Vertical Line', Icons.more_vert),
  ruler('Pip Ruler', Icons.straighten);

  final String label;
  final IconData icon;
  const DrawingTool(this.label, this.icon);
}

class ChartPoint {
  final DateTime time;
  final double price;

  const ChartPoint({required this.time, required this.price});

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'price': price,
  };

  factory ChartPoint.fromJson(Map<String, dynamic> json) => ChartPoint(
    time: DateTime.parse(json['time'] as String),
    price: (json['price'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartPoint &&
          runtimeType == other.runtimeType &&
          time == other.time &&
          price == other.price;

  @override
  int get hashCode => time.hashCode ^ price.hashCode;
}

class ChartDrawing {
  final String id;
  final DrawingTool tool;
  final List<ChartPoint> points;
  Color color;
  double strokeWidth;
  bool isLocked;
  bool isSelected;
  String? alertId;

  ChartDrawing({
    required this.id,
    required this.tool,
    required this.points,
    this.color = const Color(0xFF00E5FF), // Default Electric Cyan
    this.strokeWidth = 2.0,
    this.isLocked = false,
    this.isSelected = false,
    this.alertId,
  });

  bool get hasAlert => alertId != null && alertId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'tool': tool.name,
    'points': points.map((p) => p.toJson()).toList(),
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    'isLocked': isLocked,
    'alertId': alertId,
  };

  factory ChartDrawing.fromJson(Map<String, dynamic> json) {
    return ChartDrawing(
      id: json['id'] as String,
      tool: DrawingTool.values.firstWhere(
        (t) => t.name == json['tool'],
        orElse: () => DrawingTool.trendline,
      ),
      points: (json['points'] as List<dynamic>)
          .map((p) => ChartPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      color: Color((json['color'] as num?)?.toInt() ?? 0xFF00E5FF),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      isLocked: json['isLocked'] as bool? ?? false,
      alertId: json['alertId'] as String?,
    );
  }

  ChartDrawing copyWith({
    String? id,
    DrawingTool? tool,
    List<ChartPoint>? points,
    Color? color,
    double? strokeWidth,
    bool? isLocked,
    bool? isSelected,
    String? alertId,
  }) {
    return ChartDrawing(
      id: id ?? this.id,
      tool: tool ?? this.tool,
      points: points ?? List.from(this.points),
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isLocked: isLocked ?? this.isLocked,
      isSelected: isSelected ?? this.isSelected,
      alertId: alertId ?? this.alertId,
    );
  }
}
