import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/app_state.dart';
import 'services/config.dart';
import 'screens/home_screen.dart';
import 'branding/app_brand.dart';
import 'features/seastock/screens/stock_home_screen.dart';

/// This build opens on Seastock stock on board. Pass
/// `--dart-define=LABEL_SCANNER=true` to open on the label scanner instead,
/// with Delivery notes behind its truck icon.
const _labelScannerHome = bool.fromEnvironment('LABEL_SCANNER');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (hasSupabaseConfig) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const PixorexApp(),
    ),
  );
}

class PixorexApp extends StatelessWidget {
  const PixorexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppBrand.blue,
              brightness: Brightness.light,
            ).copyWith(
              primary: AppBrand.blue,
              onPrimary: Colors.white,
              secondary: AppBrand.accentBlue,
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: AppBrand.navy,
              outline: AppBrand.neutral,
            ),
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppBrand.background,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppBrand.neutral),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppBrand.neutral),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppBrand.blue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const EmailGate(),
    );
  }
}

class EmailGate extends StatefulWidget {
  const EmailGate({super.key});

  @override
  State<EmailGate> createState() => _EmailGateState();
}

class _EmailGateState extends State<EmailGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email');
    if (mounted) {
      final state = context.read<AppState>();
      if (email != null && email.isNotEmpty) {
        state.setUserEmail(email);
        setState(() => _checking = false);
      } else {
        setState(() => _checking = false);
        _showEmailDialog();
      }
    }
  }

  void _showEmailDialog() {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Welcome to Pixorex')),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your email to get started. This identifies your extractions.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(value.trim())) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final email = controller.text.trim();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('user_email', email);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    context.read<AppState>().setUserEmail(email);
                  }
                }
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_labelScannerHome) return const HomeScreen();
    return StockHomeScreen(operatorEmail: context.watch<AppState>().userEmail);
  }
}
