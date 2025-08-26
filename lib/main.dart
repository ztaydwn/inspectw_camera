import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/metadata_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final meta = MetadataService();
  await meta.init();
  runApp(InspectWApp(meta: meta));
}

class InspectWApp extends StatelessWidget {
  final MetadataService meta;
  const InspectWApp({super.key, required this.meta});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MetadataService>.value(value: meta),
      ],
      child: MaterialApp(
        title: 'InspectW Camera',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
