import 'user.dart';

class StreakRedemptionRequest {
  final int id;
  final User? user;
  final String amount;
  final String status;
  final String? statusLabel;
  final String? note;
  final DateTime? createdAt;

  const StreakRedemptionRequest({
    required this.id,
    this.user,
    required this.amount,
    required this.status,
    this.statusLabel,
    this.note,
    this.createdAt,
  });

  factory StreakRedemptionRequest.fromJson(Map<String, dynamic> json) {
    final userData = json['user'];
    return StreakRedemptionRequest(
      id: _parseInt(json['id']) ?? 0,
      user: userData is Map<String, dynamic> ? User.fromJson(userData) : null,
      amount: (json['amount'] ?? '0.00').toString(),
      status: (json['status'] ?? 'pending').toString(),
      statusLabel: json['status_label']?.toString(),
      note: json['note']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class LoginStreakStatus {
  final int currentStreak;
  final DateTime? lastLoginDate;
  final String receivableBonus;
  final DateTime? lastAwardedAt;
  final int targetDays;
  final String rewardAmount;
  final int daysRemaining;
  final bool rewardAvailable;
  final StreakRedemptionRequest? activeRedemptionRequest;

  const LoginStreakStatus({
    required this.currentStreak,
    this.lastLoginDate,
    required this.receivableBonus,
    this.lastAwardedAt,
    required this.targetDays,
    required this.rewardAmount,
    required this.daysRemaining,
    required this.rewardAvailable,
    this.activeRedemptionRequest,
  });

  factory LoginStreakStatus.fromJson(Map<String, dynamic> json) {
    final requestData = json['active_redemption_request'];
    return LoginStreakStatus(
      currentStreak: _parseInt(json['current_streak']) ?? 0,
      lastLoginDate: json['last_login_date'] != null
          ? DateTime.tryParse(json['last_login_date'].toString())
          : null,
      receivableBonus: (json['receivable_bonus'] ?? '0.00').toString(),
      lastAwardedAt: json['last_awarded_at'] != null
          ? DateTime.tryParse(json['last_awarded_at'].toString())
          : null,
      targetDays: _parseInt(json['target_days']) ?? 7,
      rewardAmount: (json['reward_amount'] ?? '5.00').toString(),
      daysRemaining: _parseInt(json['days_remaining']) ?? 0,
      rewardAvailable: json['reward_available'] == true,
      activeRedemptionRequest: requestData is Map<String, dynamic>
          ? StreakRedemptionRequest.fromJson(requestData)
          : null,
    );
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
