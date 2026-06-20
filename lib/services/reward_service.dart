import '../api/api_client.dart';
import '../models/login_streak.dart';

class RewardService {
  final ApiClient _apiClient;

  const RewardService(this._apiClient);

  Future<LoginStreakStatus> getStreak() async {
    final response = await _apiClient.get('/api/rewards/streak/');
    return LoginStreakStatus.fromJson(_unwrapMap(response));
  }

  Future<LoginStreakStatus> recordVisit() async {
    final response = await _apiClient.post('/api/rewards/streak/visit/');
    return LoginStreakStatus.fromJson(_unwrapMap(response));
  }

  Future<StreakRedemptionRequest> requestRedemption({String note = ''}) async {
    final response = await _apiClient.post(
      '/api/rewards/streak/redeem/',
      body: {'note': note},
    );
    return StreakRedemptionRequest.fromJson(_unwrapMap(response));
  }

  Map<String, dynamic> _unwrapMap(dynamic response) {
    final data = response is Map && response['data'] is Map
        ? response['data']
        : response;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }
}
