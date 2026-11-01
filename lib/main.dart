import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'core.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: storeName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: cream,
          colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green, secondary: lime),
          appBarTheme: const AppBarTheme(backgroundColor: cream, elevation: 0, scrolledUnderElevation: 0, foregroundColor: green),
          navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: lime),
          inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
        ),
        home: StreamBuilder<AuthState>(
          stream: sb.auth.onAuthStateChange,
          builder: (c, _) => sb.auth.currentSession == null ? const LoginScreen() : const Shell(),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
        body: IndexedStack(index: i, children: const [HomeTab(), CartTab(), OrdersTab(), AlertsTab(), ProfileTab()]),
        bottomNavigationBar: ValueListenableBuilder<Map<int, int>>(
          valueListenable: cart,
          builder: (c, m, _) => NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (v) => setState(() => i = v),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                  icon: Badge(isLabelVisible: m.isNotEmpty, label: Text('${m.values.fold(0, (a, b) => a + b)}'), child: const Icon(Icons.shopping_bag_outlined)),
                  label: 'Cart'),
              const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
              const NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Alerts'),
              const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
            ],
          ),
        ),
      );
}
