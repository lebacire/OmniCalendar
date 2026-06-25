import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'firebase_options.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// Unified account model for both Google and Outlook
class CalendarAccount {
  final String email;
  final String provider; // 'google' or 'outlook'
  final String? displayName;
  final String? accessToken;
  final GoogleSignInAccount? googleAccount;

  CalendarAccount({
    required this.email,
    required this.provider,
    this.displayName,
    this.accessToken,
    this.googleAccount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarAccount &&
          runtimeType == other.runtimeType &&
          email == other.email &&
          provider == other.provider;

  @override
  int get hashCode => email.hashCode ^ provider.hashCode;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: material.Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const CalendarPage(),
    );
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  final Map<DateTime, List<String>> _events = {};
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/calendar.readonly',
    ],
  );
  
  List<CalendarAccount> _currentUsers = [];
  Map<String, dynamic> _calendarApis = {}; // Can hold CalendarApi or OAuth tokens
  bool _isLoadingEvents = false;

  // Microsoft Azure AD configuration (update these with your app registration values)
  static const String microsoftClientId = 'YOUR_MICROSOFT_CLIENT_ID'; // Update this
  static const String microsoftTenantId = 'common'; // or your tenant ID
  static const String redirectUrl = 'com.example.flutter_tes_app://auth';
  static const String authorizationEndpoint = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
  static const String tokenEndpoint = 'https://login.microsoftonline.com/common/oauth2/v2.0/token';

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _setupGoogleListener();
    _checkSignedInUsers();
    // Initialize webview for Android
    if (material.defaultTargetPlatform == material.TargetPlatform.android) {
      WebViewController.platform = AndroidWebViewController();
    }
  }

  void _setupGoogleListener() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      print('Google account changed: $account');
      if (account != null) {
        final calendarAccount = CalendarAccount(
          email: account.email,
          provider: 'google',
          googleAccount: account,
        );
        final isNewAccount = !_currentUsers.any((u) => u.email == account.email);
        if (isNewAccount) {
          setState(() {
            _currentUsers.add(calendarAccount);
            print('Added Google account: ${account.email}');
          });
          _initializeGoogleCalendarApi(calendarAccount);
        }
      }
    });
  }

  Future<void> _checkSignedInUsers() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        final calendarAccount = CalendarAccount(
          email: account.email,
          provider: 'google',
          googleAccount: account,
        );
        if (!_currentUsers.any((u) => u.email == account.email)) {
          setState(() {
            _currentUsers.add(calendarAccount);
            print('Silently signed in: ${account.email}');
          });
          _initializeGoogleCalendarApi(calendarAccount);
        }
      }
    } catch (e) {
      print('Silent sign-in error: $e');
    }
  }

  Future<void> _initializeGoogleCalendarApi(CalendarAccount account) async {
    try {
      if (account.googleAccount == null) return;
      final authHeaders = await account.googleAccount!.authHeaders;
      final authenticateClient = _GoogleHttpClient(authHeaders);
      _calendarApis[account.email] = calendar.CalendarApi(authenticateClient);
      _fetchGoogleCalendarEvents(account.email);
    } catch (e) {
      print('Error initializing Google Calendar API for ${account.email}: $e');
    }
  }

  Future<void> _initializeOutlookCalendarApi(CalendarAccount account) async {
    try {
      if (account.accessToken == null) return;
      _calendarApis[account.email] = account.accessToken;
      _fetchOutlookCalendarEvents(account.email);
    } catch (e) {
      print('Error initializing Outlook Calendar API for ${account.email}: $e');
    }
  }

  Future<void> _fetchGoogleCalendarEvents(String accountEmail) async {
    if (_calendarApis[accountEmail] == null) return;
    if (_calendarApis[accountEmail] is! calendar.CalendarApi) return;

    setState(() {
      _isLoadingEvents = true;
    });

    try {
      final now = DateTime.now();
      final timeMin = DateTime(now.year, now.month, now.day);
      final timeMax = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 365));

      final events = await _calendarApis[accountEmail]!.events.list(
        'primary',
        timeMin: timeMin,
        timeMax: timeMax,
      );

      setState(() {
        if (events.items != null) {
          for (var event in events.items!) {
            if (event.start?.dateTime != null) {
              final eventDate = DateTime(
                event.start!.dateTime!.year,
                event.start!.dateTime!.month,
                event.start!.dateTime!.day,
              );
              if (_events[eventDate] == null) {
                _events[eventDate] = [];
              }
              _events[eventDate]!.add(
                '${event.summary ?? 'Untitled Event'} (Google: $accountEmail)',
              );
            }
          }
        }
      });
    } catch (e) {
      print('Error fetching Google Calendar events for $accountEmail: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching Google events: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoadingEvents = false;
      });
    }
  }

  Future<void> _fetchOutlookCalendarEvents(String accountEmail) async {
    final accessToken = _calendarApis[accountEmail];
    if (accessToken == null || accessToken is! String) return;

    setState(() {
      _isLoadingEvents = true;
    });

    try {
      final now = DateTime.now();
      final timeMin = DateTime(now.year, now.month, now.day);
      final timeMax = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 365));

      final response = await http.get(
        Uri.parse(
          'https://graph.microsoft.com/v1.0/me/calendarview'
          '?startDateTime=${timeMin.toIso8601String()}'
          '&endDateTime=${timeMax.toIso8601String()}',
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['value'] as List<dynamic>;

        setState(() {
          for (var event in items) {
            final startTime = event['start']?['dateTime'];
            if (startTime != null) {
              final eventDateTime = DateTime.parse(startTime);
              final eventDate = DateTime(
                eventDateTime.year,
                eventDateTime.month,
                eventDateTime.day,
              );
              if (_events[eventDate] == null) {
                _events[eventDate] = [];
              }
              _events[eventDate]!.add(
                '${event['subject'] ?? 'Untitled Event'} (Outlook: $accountEmail)',
              );
            }
          }
        });
      } else if (response.statusCode == 401) {
        print('Outlook token expired, attempting refresh...');
      } else {
        print('Error fetching Outlook events: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching Outlook Calendar events for $accountEmail: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching Outlook events: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoadingEvents = false;
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      print('Starting Google sign-in...');
      await _googleSignIn.disconnect();
      final account = await _googleSignIn.signIn();

      if (account != null) {
        print('Signed in to Google: ${account.email}');
        final calendarAccount = CalendarAccount(
          email: account.email,
          provider: 'google',
          googleAccount: account,
        );
        final isNewAccount = !_currentUsers.any((u) => u.email == account.email);
        if (isNewAccount) {
          setState(() {
            _currentUsers.add(calendarAccount);
          });
          _initializeGoogleCalendarApi(calendarAccount);
        } else {
          print('Google account already added: ${account.email}');
        }
      }
    } catch (error) {
      print('Google sign in error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign in failed: $error')),
        );
      }
    }
  }

  Future<void> _handleOutlookSignIn() async {
    try {
      print('Starting Outlook sign-in...');

      if (microsoftClientId == 'YOUR_MICROSOFT_CLIENT_ID') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Outlook sign-in not configured. Update microsoftClientId in main.dart',
              ),
            ),
          );
        }
        return;
      }

      // Open webview for OAuth
      if (!mounted) return;
      
      final result = await Navigator.of(context).push<String>(
        material.MaterialPageRoute(
          builder: (context) => _OutlookOAuthPage(
            clientId: microsoftClientId,
            redirectUrl: redirectUrl,
          ),
        ),
      );

      if (result != null && result.isNotEmpty) {
        // Extract access token from result
        final accessToken = result;
        
        // Get user info
        final userInfoResponse = await http.get(
          Uri.parse('https://graph.microsoft.com/v1.0/me'),
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        );

        if (userInfoResponse.statusCode == 200) {
          final userInfo = jsonDecode(userInfoResponse.body);
          final email = userInfo['mail'] ?? userInfo['userPrincipalName'];
          final displayName = userInfo['displayName'];

          print('Signed in to Outlook: $email');
          final calendarAccount = CalendarAccount(
            email: email,
            provider: 'outlook',
            displayName: displayName,
            accessToken: accessToken,
          );

          final isNewAccount =
              !_currentUsers.any((u) => u.email == email && u.provider == 'outlook');
          if (isNewAccount) {
            setState(() {
              _currentUsers.add(calendarAccount);
            });
            _initializeOutlookCalendarApi(calendarAccount);
          } else {
            print('Outlook account already added: $email');
          }
        }
      }
    } catch (error) {
      print('Outlook sign in error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Outlook sign in failed: $error')),
        );
      }
    }
  }

  Future<void> _handleSignOut(CalendarAccount account) async {
    try {
      print('Signing out: ${account.email} (${account.provider})');

      if (account.provider == 'google') {
        final currentUser = await _googleSignIn.currentUser;
        if (currentUser?.email == account.email) {
          await _googleSignIn.signOut();
        }
      }

      setState(() {
        _currentUsers.removeWhere(
          (u) => u.email == account.email && u.provider == account.provider,
        );
        _calendarApis.remove(account.email);
        if (_currentUsers.isEmpty) {
          _events.clear();
        }
      });
    } catch (e) {
      print('Sign out error: $e');
    }
  }

  List<String> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _events[normalizedDay] ?? [];
  }

  void _addEvent() {
    showDialog(
      context: context,
      builder: (context) {
        String eventName = '';
        return AlertDialog(
          title: const Text('Add Event'),
          content: TextField(
            onChanged: (value) => eventName = value,
            decoration: const InputDecoration(
              hintText: 'Enter event name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (eventName.isNotEmpty) {
                  setState(() {
                    if (_events[_selectedDay] == null) {
                      _events[_selectedDay] = [];
                    }
                    _events[_selectedDay]!.add(eventName);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Calendar'),
        centerTitle: true,
        actions: [
          if (_currentUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: PopupMenuButton<String>(
                onSelected: (accountKey) {
                  final accountParts = accountKey.split('|');
                  final email = accountParts[0];
                  final provider = accountParts[1];
                  final account = _currentUsers.firstWhere(
                    (u) => u.email == email && u.provider == provider,
                  );
                  _handleSignOut(account);
                },
                itemBuilder: (BuildContext context) => _currentUsers.map((user) {
                  return PopupMenuItem<String>(
                    value: '${user.email}|${user.provider}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.email,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                user.provider.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: material.Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.logout, size: 16),
                      ],
                    ),
                  );
                }).toList(),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text(
                      '${_currentUsers.length} Account${_currentUsers.length > 1 ? 's' : ''}',
                      style: TextStyle(color: material.Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: PopupMenuButton<String>(
              onSelected: (provider) {
                if (provider == 'google') {
                  _handleGoogleSignIn();
                } else if (provider == 'outlook') {
                  _handleOutlookSignIn();
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'google',
                  child: Row(
                    children: [
                      Icon(Icons.mail, size: 18),
                      SizedBox(width: 8),
                      Text('Add Google Calendar'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'outlook',
                  child: Row(
                    children: [
                      Icon(Icons.mail, size: 18),
                      SizedBox(width: 8),
                      Text('Add Outlook Calendar'),
                    ],
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _currentUsers.isEmpty ? 'Sign In' : '+ Add',
                  style: TextStyle(color: material.Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_isLoadingEvents)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: (day) => _getEventsForDay(day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: TextStyle(color: material.Colors.red),
                markersMaxCount: 1,
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Total Events: ${_events.length}',
                style: TextStyle(fontSize: 12, color: material.Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Selected: ${DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Events',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_getEventsForDay(_selectedDay).isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('No events for this day'),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _getEventsForDay(_selectedDay).length,
                  itemBuilder: (context, index) {
                    return Dismissible(
                      key: Key(
                        _getEventsForDay(_selectedDay)[index] + index.toString(),
                      ),
                      onDismissed: (direction) {
                        setState(() {
                          _events[_selectedDay]!.removeAt(index);
                        });
                      },
                      child: Card(
                        child: ListTile(
                          title: Text(_getEventsForDay(_selectedDay)[index]),
                          trailing: const Icon(Icons.delete),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        tooltip: 'Add Event',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// OAuth page for Outlook authentication using webview
class _OutlookOAuthPage extends StatefulWidget {
  final String clientId;
  final String redirectUrl;

  const _OutlookOAuthPage({
    required this.clientId,
    required this.redirectUrl,
  });

  @override
  State<_OutlookOAuthPage> createState() => _OutlookOAuthPageState();
}

class _OutlookOAuthPageState extends State<_OutlookOAuthPage> {
  late WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            print('Page finished: $url');
            _checkForToken(url);
          },
          onWebResourceError: (WebResourceError error) {
            print('Web resource error: ${error.description}');
          },
        ),
      );

    final authUrl = _buildAuthUrl();
    _webViewController.loadRequest(Uri.parse(authUrl));
  }

  String _buildAuthUrl() {
    final params = {
      'client_id': widget.clientId,
      'response_type': 'code',
      'redirect_uri': widget.redirectUrl,
      'scope': 'offline_access Calendars.Read',
      'response_mode': 'query',
    };

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize?$queryString';
  }

  void _checkForToken(String url) {
    if (url.startsWith(widget.redirectUrl)) {
      print('Redirect URL detected: $url');
      final uri = Uri.parse(url);
      final code = uri.queryParameters['code'];

      if (code != null) {
        _exchangeCodeForToken(code);
      } else {
        final error = uri.queryParameters['error'];
        if (error != null) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Authorization error: $error')),
          );
        }
      }
    }
  }

  Future<void> _exchangeCodeForToken(String code) async {
    try {
      final tokenUrl = Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/token');
      final response = await http.post(
        tokenUrl,
        body: {
          'client_id': widget.clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': widget.redirectUrl,
          'scope': 'offline_access Calendars.Read',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'];
        print('Access token obtained');
        Navigator.of(context).pop(accessToken);
      } else {
        print('Token exchange failed: ${response.body}');
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error exchanging code: $e');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in to Outlook'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: WebViewWidget(controller: _webViewController),
    );
  }
}

class _GoogleHttpClient extends http.BaseClient {
  final Map<String, String> _headers;

  _GoogleHttpClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(_headers);
    return await request.send();
  }
}
