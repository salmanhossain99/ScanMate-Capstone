import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtl;
  late final TextEditingController _emailCtl;
  late final TextEditingController _idCtl;
  final TextEditingController _passwordCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = context.read<UserProvider>();
    _nameCtl = TextEditingController(text: user.name ?? '');
    _emailCtl = TextEditingController(text: user.email ?? '');
    _idCtl = TextEditingController(text: user.studentId ?? '');
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _idCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_nameCtl, 'Name', Icons.person_outline),
              const SizedBox(height: 12),
              _field(_emailCtl, 'Email', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _field(_idCtl, 'Student ID', Icons.badge_outlined, keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _field(_passwordCtl, 'New Password (optional)', Icons.lock_outline, isRequired: false),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    await context.read<UserProvider>().updateAccount(
                          name: _nameCtl.text,
                          email: _emailCtl.text,
                          studentId: _idCtl.text,
                          password: _passwordCtl.text.isEmpty ? null : _passwordCtl.text,
                        );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account updated')));
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctl, String hint, IconData icon, {TextInputType keyboardType = TextInputType.text, bool isRequired = true}) {
    return TextFormField(
      controller: ctl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        if (!isRequired) return null;
        if (v == null || v.isEmpty) return 'Required';
        if (hint == 'Email' && !v.contains('@')) return 'Enter valid email';
        return null;
      },
    );
  }
}


