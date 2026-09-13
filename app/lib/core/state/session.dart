import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/club_role.dart';
import '../models/department.dart';
import '../models/member.dart';

enum SessionState {
  /// Reading the saved token before the first frame.
  restoring,

  /// No valid session — show sign-in.
  signedOut,

  /// Signed in but the account has not been approved yet (Section 4.2).
  pendingApproval,

  /// Fully signed in and approved.
  active,
}

/// Who is signed in, and the token that proves it.
///
/// Deliberately separate from [ClubStore]: signing out must be able to throw
/// away every scrap of club data without the auth flow depending on any of it.
class Session extends ChangeNotifier {
  Session({ApiClient? api}) {
    _api = api ??
        ApiClient(
          baseUrlProvider: () => baseUrl,
          tokenProvider: () => _token,
          onUnauthorized: _onUnauthorized,
        );
  }

  static const _tokenKey = 'gwd.session.token';
  static const _userKey = 'gwd.session.user';
  static const _serverKey = 'gwd.session.server';

  /// A server address the user set by hand, overriding the built-in default.
  ///
  /// This exists because the address is otherwise baked in at build time: when
  /// the router reassigns the laptop's IP, every installed copy silently stops
  /// working. Being able to retype it beats reinstalling.
  String? _serverOverride;

  String get baseUrl => _serverOverride ?? ApiConfig.resolve();
  String? get serverOverride => _serverOverride;
  bool get usingCustomServer => _serverOverride != null;

  late final ApiClient _api;
  ApiClient get api => _api;

  String? _token;
  Member? _me;
  Department? _department;
  SessionState _state = SessionState.restoring;
  String? _error;
  bool _busy = false;

  int pointsPerTask = 5;
  String clubName = 'GWD Club';

  Member? get me => _me;
  Department? get department => _department;
  SessionState get state => _state;
  String? get error => _error;
  bool get busy => _busy;
  String? get token => _token;
  ClubRole get role => _me?.role ?? ClubRole.clubMember;
  bool get isSignedIn => _token != null && _me != null;

  void _set(SessionState next) {
    _state = next;
    notifyListeners();
  }

  void _onUnauthorized() {
    // The server rejected our token; do not leave the UI in a half-signed-in
    // state showing empty lists.
    if (_state != SessionState.signedOut) {
      signOut();
    }
  }

  /// Restore before the first frame so the app never flashes sign-in at
  /// somebody who is already signed in.
  /// Point the app at a different server. Returns false if the address is not
  /// usable, so the caller can say so rather than silently doing nothing.
  Future<bool> setServer(String? input) async {
    final prefs = await SharedPreferences.getInstance();
    if (input == null || input.trim().isEmpty) {
      _serverOverride = null;
      await prefs.remove(_serverKey);
      _error = null;
      notifyListeners();
      return true;
    }
    final normalised = ApiConfig.normalise(input);
    if (normalised == null) return false;
    _serverOverride = normalised;
    await prefs.setString(_serverKey, normalised);
    _error = null;
    notifyListeners();
    return true;
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverOverride = prefs.getString(_serverKey);
      _token = prefs.getString(_tokenKey);
      final cached = prefs.getString(_userKey);
      if (cached != null) {
        try {
          _me = Member.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        } catch (_) {
          _me = null;
        }
      }
      if (_token == null || _me == null) {
        _set(SessionState.signedOut);
        return;
      }
      // Show the cached identity immediately, then confirm with the server.
      _set(_me!.approvalStatus == ApprovalStatus.approved
          ? SessionState.active
          : SessionState.pendingApproval);
      await refresh();
    } catch (_) {
      _set(SessionState.signedOut);
    }
  }

  /// Re-read the account. Approval may have been granted since last launch.
  Future<void> refresh() async {
    if (_token == null) return;
    try {
      final json = await _api.get('/api/auth/me');
      _applyUser(json['user'] as Map<String, dynamic>?);
      final dept = json['department'] as Map<String, dynamic>?;
      _department = dept == null ? null : Department.fromJson(dept);
      final config = json['config'] as Map<String, dynamic>?;
      if (config != null) {
        pointsPerTask = (config['pointsPerTask'] as num?)?.toInt() ?? pointsPerTask;
        clubName = config['clubName'] as String? ?? clubName;
      }
      await _persist();
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isAuthFailure) await signOut();
    } catch (_) {
      // Offline: keep the cached identity rather than kicking the user out.
    }
  }

  /// Swap in a token the server handed back mid-session.
  ///
  /// Changing your password revokes every token issued before it — including
  /// the one that made the request. The server returns a replacement, and
  /// without adopting it here the very act of succeeding would sign you out.
  Future<void> adoptToken(String token, {Map<String, dynamic>? user}) async {
    _token = token;
    if (user != null) _applyUser(user);
    await _persist();
    notifyListeners();
  }

  void _applyUser(Map<String, dynamic>? json) {
    if (json == null) return;
    _me = Member.fromJson(json);
    _state = _me!.approvalStatus == ApprovalStatus.approved
        ? SessionState.active
        : SessionState.pendingApproval;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString(_tokenKey, _token!);
    final me = _me;
    if (me != null) {
      await prefs.setString(
        _userKey,
        jsonEncode({
          'id': me.id,
          'name': me.name,
          'email': me.email,
          'phone': me.phone,
          'role': me.role.wire,
          'departmentId': me.departmentId,
          'points': me.points,
          'approvalStatus': me.approvalStatus.name,
          'avatarColor': me.avatarColor,
        }),
      );
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final json = await _api.post('/api/auth/login', {'email': email, 'password': password});
      _token = json['token'] as String?;
      _applyUser(json['user'] as Map<String, dynamic>?);
      await _persist();
      await refresh();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ask a Director or the President to reset your password.
  ///
  /// No account is required and the server answers identically whether or not
  /// the address exists, so this cannot be used to discover who has one.
  Future<void> requestPasswordReset(String email) async {
    await _api.post('/api/auth/password/forgot', {'email': email});
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
    required ClubRole role,
    String? departmentId,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final json = await _api.post('/api/auth/signup', {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role.wire,
        if (departmentId != null) 'departmentId': departmentId,
      });
      _token = json['token'] as String?;
      _applyUser(json['user'] as Map<String, dynamic>?);
      await _persist();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// The list of departments a signup can choose from. Public on purpose: the
  /// user has no account yet at the moment they must pick one.
  Future<List<Department>> publicDepartments() async {
    try {
      final json = await _api.get('/api/departments/public');
      return listFrom(json, 'departments', Department.fromJson);
    } catch (_) {
      return const [];
    }
  }

  Future<void> signOut() async {
    _token = null;
    _me = null;
    _department = null;
    _error = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    _set(SessionState.signedOut);
  }

  /// Applied when the socket reports our own user document changed — e.g.
  /// points were credited, or approval came through while the app was open.
  void applyLiveUser(Map<String, dynamic> data) {
    final me = _me;
    if (me == null || data['id'] != me.id) return;
    final status = ApprovalStatus.fromWire(data['approvalStatus'] as String?);
    _me = me.copyWith(
      points: (data['points'] as num?)?.toInt(),
      role: data['role'] == null ? null : ClubRole.fromWire(data['role'] as String?),
      approvalStatus: status,
    );
    if (status == ApprovalStatus.approved && _state == SessionState.pendingApproval) {
      _state = SessionState.active;
    }
    _persist();
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
