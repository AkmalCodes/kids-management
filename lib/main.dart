import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Beginner Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BeginnerShowcaseScreen(),
    );
  }
}

class BeginnerShowcaseScreen extends StatefulWidget {
  const BeginnerShowcaseScreen({super.key});

  @override
  State<BeginnerShowcaseScreen> createState() => _BeginnerShowcaseScreenState();
}

class _BeginnerShowcaseScreenState extends State<BeginnerShowcaseScreen> {
  // STATE VARIABLES — these drive the interactive widgets below
  int _counter = 0;
  bool _switchValue = false;
  bool _checkboxValue = false;
  double _sliderValue = 0.5;
  String _textFieldValue = '';
  Color _boxColor = Colors.blue;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showAlertDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hello!'),
        content: const Text('This is an AlertDialog. Tap OK to close it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── APP BAR ────────────────────────────────────────────────────────────
      appBar: AppBar(
        title: const Text('Flutter Beginner Showcase'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Show dialog',
            onPressed: _showAlertDialog,
          ),
        ],
      ),

      // ── FLOATING ACTION BUTTON ─────────────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSnackBar('FloatingActionButton tapped!'),
        tooltip: 'Show SnackBar',
        child: const Icon(Icons.notifications),
      ),

      // ── BODY ───────────────────────────────────────────────────────────────
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 1. TEXT & TYPOGRAPHY ─────────────────────────────────────────
          _SectionHeader(title: '1. Text & Typography'),
          const Text('Plain text — no style'),
          const SizedBox(height: 6),
          const Text(
            'Bold + large',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Italic + colored',
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Colors.purple,
            ),
          ),
          const Text(
            'Underline + letter spacing',
            style: TextStyle(
              decoration: TextDecoration.underline,
              letterSpacing: 3,
            ),
          ),
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 16, color: Colors.black),
              children: [
                TextSpan(text: 'RichText: '),
                TextSpan(
                  text: 'red ',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                TextSpan(text: '+ '),
                TextSpan(
                  text: 'blue',
                  style: TextStyle(color: Colors.blue, fontStyle: FontStyle.italic),
                ),
                TextSpan(text: ' in one line.'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 2. BUTTONS ───────────────────────────────────────────────────
          _SectionHeader(title: '2. Buttons'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton(
                onPressed: () => _showSnackBar('ElevatedButton!'),
                child: const Text('ElevatedButton'),
              ),
              OutlinedButton(
                onPressed: () => _showSnackBar('OutlinedButton!'),
                child: const Text('OutlinedButton'),
              ),
              TextButton(
                onPressed: () => _showSnackBar('TextButton!'),
                child: const Text('TextButton'),
              ),
              IconButton(
                icon: const Icon(Icons.thumb_up, color: Colors.blue),
                tooltip: 'IconButton',
                onPressed: () => _showSnackBar('IconButton!'),
              ),
              ElevatedButton.icon(
                onPressed: () => _showSnackBar('Button with icon!'),
                icon: const Icon(Icons.star),
                label: const Text('With Icon'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 3. COUNTER (setState) ────────────────────────────────────────
          _SectionHeader(title: '3. State — Counter (setState)'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle, size: 36, color: Colors.red),
                onPressed: () => setState(() => _counter--),
              ),
              const SizedBox(width: 16),
              Text(
                '$_counter',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.add_circle, size: 36, color: Colors.green),
                onPressed: () => setState(() => _counter++),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 4. TEXT FIELD ────────────────────────────────────────────────
          _SectionHeader(title: '4. TextField (Input)'),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Type something…',
              hintText: 'Your text here',
              prefixIcon: Icon(Icons.edit),
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => setState(() => _textFieldValue = val),
          ),
          if (_textFieldValue.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('You typed: "$_textFieldValue"',
                style: const TextStyle(color: Colors.indigo)),
          ],
          const SizedBox(height: 16),

          // ── 5. INTERACTIVE CONTROLS ─────────────────────────────────────
          _SectionHeader(title: '5. Interactive Controls'),
          SwitchListTile(
            title: const Text('Switch'),
            subtitle: Text(_switchValue ? 'ON' : 'OFF'),
            value: _switchValue,
            onChanged: (val) => setState(() => _switchValue = val),
          ),
          CheckboxListTile(
            title: const Text('Checkbox'),
            subtitle: Text(_checkboxValue ? 'Checked' : 'Unchecked'),
            value: _checkboxValue,
            onChanged: (val) => setState(() => _checkboxValue = val ?? false),
          ),
          ListTile(
            title: const Text('Slider'),
            subtitle: Slider(
              value: _sliderValue,
              onChanged: (val) => setState(() => _sliderValue = val),
            ),
            trailing: Text('${(_sliderValue * 100).round()}%'),
          ),
          const SizedBox(height: 16),

          // ── 6. COLORS & CONTAINERS ───────────────────────────────────────
          _SectionHeader(title: '6. Containers, Colors & BoxDecoration'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final color in [Colors.red, Colors.green, Colors.blue, Colors.orange])
                GestureDetector(
                  onTap: () => setState(() => _boxColor = color),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _boxColor == color
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 80,
            decoration: BoxDecoration(
              color: _boxColor,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Tap a circle to change my color!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),

          // ── 7. LAYOUT — ROW & COLUMN ─────────────────────────────────────
          _SectionHeader(title: '7. Layout — Row & Column'),
          const Text('Row (horizontal):'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ColoredBox(color: Colors.pink, label: 'A'),
              _ColoredBox(color: Colors.teal, label: 'B'),
              _ColoredBox(color: Colors.amber, label: 'C'),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Column (vertical):'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ColoredBox(color: Colors.purple, label: 'X'),
              const SizedBox(height: 6),
              _ColoredBox(color: Colors.cyan, label: 'Y'),
              const SizedBox(height: 6),
              _ColoredBox(color: Colors.lime, label: 'Z'),
            ],
          ),
          const SizedBox(height: 16),

          // ── 8. STACK ─────────────────────────────────────────────────────
          _SectionHeader(title: '8. Stack (layers)'),
          SizedBox(
            height: 100,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Text('Bottom layer', style: TextStyle(color: Colors.blue)),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Middle',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const Positioned(
                  bottom: 8,
                  right: 8,
                  child: Icon(Icons.layers, color: Colors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 9. CARD & LIST TILE ──────────────────────────────────────────
          _SectionHeader(title: '9. Card & ListTile'),
          Card(
            elevation: 4,
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: const Text('ListTile Title'),
                  subtitle: const Text('This is the subtitle'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSnackBar('ListTile tapped!'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: const Text('Another ListTile'),
                  trailing: Switch(
                    value: _switchValue,
                    onChanged: (val) => setState(() => _switchValue = val),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 10. ICONS ────────────────────────────────────────────────────
          _SectionHeader(title: '10. Icons'),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: const [
              Icon(Icons.home, size: 32, color: Colors.blue),
              Icon(Icons.favorite, size: 32, color: Colors.red),
              Icon(Icons.star, size: 32, color: Colors.amber),
              Icon(Icons.camera, size: 32, color: Colors.green),
              Icon(Icons.music_note, size: 32, color: Colors.purple),
              Icon(Icons.map, size: 32, color: Colors.teal),
              Icon(Icons.shopping_cart, size: 32, color: Colors.orange),
              Icon(Icons.send, size: 32, color: Colors.indigo),
            ],
          ),
          const SizedBox(height: 16),

          // ── 11. NAVIGATION ───────────────────────────────────────────────
          _SectionHeader(title: '11. Navigation (push a new screen)'),
          ElevatedButton.icon(
            icon: const Icon(Icons.navigate_next),
            label: const Text('Go to Second Screen'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SecondScreen()),
            ),
          ),
          const SizedBox(height: 80), // padding for FAB
        ],
      ),
    );
  }
}

// ── REUSABLE HELPERS ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}

class _ColoredBox extends StatelessWidget {
  const _ColoredBox({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

// ── SECOND SCREEN (navigation demo) ──────────────────────────────────────────

class SecondScreen extends StatelessWidget {
  const SecondScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Second Screen'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 20),
            const Text(
              'You navigated here!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Navigator.push() takes you forward.\nNavigator.pop() takes you back.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
