import 'package:flutter/material.dart';

import '../services/tapo_service.dart';
import '../theme/app_theme.dart';

/// Throwaway screen for testing the local KLAP connection to a Tapo plug
/// before wiring [TapoService] into [AutomationEngine]. Not meant to
/// ship — point `home:` at this temporarily (see main.dart), run your
/// tests, then switch it back to `MainShell` once you've confirmed the
/// handshake works against your actual plug.
class TapoTestScreen extends StatefulWidget {
  const TapoTestScreen({super.key});

  @override
  State<TapoTestScreen> createState() => _TapoTestScreenState();
}

class _TapoTestScreenState extends State<TapoTestScreen> {
  final _ipController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tapo = TapoService();

  bool _busy = false;
  String? _resultMessage;
  bool _resultIsError = false;

  @override
  void dispose() {
    _ipController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Returns the three inputs trimmed, or null (after showing an inline
  /// error) if any of them are blank.
  Map<String, String>? _readInputs() {
    final ip = _ipController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (ip.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _resultMessage = 'Fill in IP, e-mail, and password first.';
        _resultIsError = true;
      });
      return null;
    }
    return {'ip': ip, 'email': email, 'password': password};
  }

  Future<void> _runTest() async {
    final inputs = _readInputs();
    if (inputs == null) return;
    setState(() {
      _busy = true;
      _resultMessage = null;
    });
    final message = await _tapo.test(
      ip: inputs['ip']!,
      email: inputs['email']!,
      password: inputs['password']!,
    );
    setState(() {
      _busy = false;
      _resultMessage = message;
      _resultIsError = !message.startsWith('Connected');
    });
  }

  Future<void> _setOn(bool on) async {
    final inputs = _readInputs();
    if (inputs == null) return;
    setState(() {
      _busy = true;
      _resultMessage = null;
    });
    final success = await _tapo.setOn(
      ip: inputs['ip']!,
      email: inputs['email']!,
      password: inputs['password']!,
      on: on,
    );
    setState(() {
      _busy = false;
      _resultMessage = success
          ? 'Plug turned ${on ? 'ON' : 'OFF'} successfully.'
          : 'Failed to turn the plug ${on ? 'on' : 'off'} — check the '
              'debug console for the detailed error.';
      _resultIsError = !success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tapo KLAP Test')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'These credentials are only used for this local test run — '
                'nothing here gets saved.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _buildField(
                _ipController,
                'Plug IP address (e.g. 192.168.1.50)',
                Icons.wifi,
                TextInputType.text,
              ),
              const SizedBox(height: 12),
              _buildField(
                _emailController,
                'TP-Link account e-mail',
                Icons.email_outlined,
                TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _buildField(
                _passwordController,
                'TP-Link account password',
                Icons.lock_outline,
                TextInputType.text,
                obscure: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _busy ? null : _runTest,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Test Connection'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _setOn(true),
                      icon: const Icon(Icons.power, color: Colors.green),
                      label: const Text('Turn ON'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _setOn(false),
                      icon: const Icon(Icons.power_off, color: Colors.redAccent),
                      label: const Text('Turn OFF'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_busy) const Center(child: CircularProgressIndicator()),
              if (_resultMessage != null) _buildResultCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon,
    TextInputType keyboardType, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: Colors.white70),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.teal, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final color = _resultIsError ? Colors.redAccent : Colors.green;
    return Card(
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _resultIsError ? Icons.error_outline : Icons.check_circle_outline,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _resultMessage!,
                style: TextStyle(color: color.withOpacity(0.9)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}