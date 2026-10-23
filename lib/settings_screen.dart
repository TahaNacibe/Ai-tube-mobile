import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';
import 'profile_avatar.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.preferences,
    required this.onSave,
    super.key,
  });

  final Map<String, dynamic> preferences;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _address;
  late final TextEditingController _name;
  late final TextEditingController _profileName;
  late final TextEditingController _profilePersona;
  late final TextEditingController _profileContext;
  late final TextEditingController _profileAvatar;
  late final Map<String, dynamic> _preferences;
  final ImagePicker _imagePicker = ImagePicker();
  List<String> _models = [];
  String _selectedModel = '';
  String _status = '';
  String _error = '';
  bool _checking = false;
  bool _saving = false;
  String _profilePhotoError = '';

  @override
  void initState() {
    super.initState();
    _preferences = Map<String, dynamic>.from(widget.preferences);
    _address = TextEditingController(
      text: _preferences['apiBaseUrl'] as String? ?? '',
    );
    _name = TextEditingController(
      text: _preferences['assistantName'] as String? ?? 'Assistant',
    );
    _profileName = TextEditingController(
      text: _preferences['profileName'] as String? ?? '',
    );
    _profilePersona = TextEditingController(
      text: _preferences['profilePersona'] as String? ?? '',
    );
    _profileContext = TextEditingController(
      text: _preferences['profileContext'] as String? ?? '',
    );
    _profileAvatar = TextEditingController(
      text: (_preferences['profileAvatar'] as String? ?? '').startsWith('data:')
          ? ''
          : _preferences['profileAvatar'] as String? ?? '',
    );
    _checkConnection(loadModels: true);
  }

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    _profileName.dispose();
    _profilePersona.dispose();
    _profileContext.dispose();
    _profileAvatar.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    _preferences['apiBaseUrl'] = _address.text.trim();
    await widget.onSave(Map<String, dynamic>.from(_preferences));
  }

  Future<void> _checkConnection({bool loadModels = false}) async {
    setState(() {
      _checking = true;
      _error = '';
      _status = '';
    });
    final api = ApiClient(_address.text);
    try {
      await api.checkConnection();
      await _persist();
      if (loadModels) {
        try {
          final result = await api.getJson('/api/models');
          _models = (result['models'] as List<dynamic>? ?? [])
              .whereType<String>()
              .toList();
          _selectedModel = result['selected'] as String? ?? '';
        } catch (error) {
          _status = 'Server connected; model status unavailable.';
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      }
      if (mounted && _status.isEmpty) {
        setState(() => _status = 'Connected to AI Tube server.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _changeModel(String? model) async {
    if (model == null || model.isEmpty) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final result = await ApiClient(
        _address.text,
      ).postJson('/api/model', {'model': model});
      setState(() {
        _selectedModel = result['selected'] as String? ?? model;
        _models = (result['models'] as List<dynamic>? ?? _models)
            .whereType<String>()
            .toList();
        _status = 'Model switched to $_selectedModel.';
      });
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndClose() async {
    setState(() => _saving = true);
    await _persist();
    if (mounted) Navigator.pop(context, _preferences);
  }

  Future<void> _updatePreference(String key, bool value) async {
    setState(() => _preferences[key] = value);
    await widget.onSave(Map<String, dynamic>.from(_preferences));
  }

  Future<void> _updateProfile(String key, String value) async {
    if (key == 'profileAvatar' && value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !const {'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        return;
      }
    }
    setState(() => _preferences[key] = value);
    await widget.onSave(Map<String, dynamic>.from(_preferences));
  }

  Future<void> _chooseProfilePhoto() async {
    setState(() => _profilePhotoError = '');
    try {
      final selected = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (bytes.length > 500_000) {
        setState(
          () => _profilePhotoError =
              'That photo is too large. Choose an image under 500 KB.',
        );
        return;
      }
      final image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _profileAvatar.clear();
      setState(() {
        _preferences['profileAvatar'] = image;
        _profilePhotoError = '';
      });
      await widget.onSave(Map<String, dynamic>.from(_preferences));
    } on PlatformException catch (error) {
      setState(
        () => _profilePhotoError =
            'Could not select photo: ${error.message ?? error.code}',
      );
    } on MissingPluginException catch (error) {
      setState(
        () => _profilePhotoError =
            'Photo selection is unavailable: ${error.message ?? 'plugin not initialized'}',
      );
    } on FileSystemException catch (error) {
      setState(
        () => _profilePhotoError =
            'Could not read the selected photo: ${error.message}',
      );
    }
  }

  Future<void> _removeProfilePhoto() async {
    _profileAvatar.clear();
    setState(() {
      _preferences['profileAvatar'] = '';
      _profilePhotoError = '';
    });
    await widget.onSave(Map<String, dynamic>.from(_preferences));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _preferences['darkModeEnabled'] == true;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to chat',
          onPressed: _saveAndClose,
        ),
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveAndClose,
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          const _SectionHeader(label: 'CONNECTION'),
          Text(
            'Connect to the AI Tube server running on your computer.',
            style: TextStyle(color: Theme.of(context).hintColor, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _checkConnection(loadModels: true),
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: 'http://192.168.1.20:8000',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _checking
                ? null
                : () => _checkConnection(loadModels: true),
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(_checking ? 'Checking…' : 'Test connection'),
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _status,
                style: TextStyle(color: appAccent(context), fontSize: 12),
              ),
            ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error,
                style: const TextStyle(color: Color(0xffa84e3b), fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'On a physical phone, use your computer’s Wi-Fi IP address (not localhost). Restart the desktop app after updating it to enable mobile access. Only connect on a trusted network.',
              style: TextStyle(fontSize: 11, height: 1.55),
            ),
          ),
          const SizedBox(height: 28),
          const _SectionHeader(label: 'AI PROFILE'),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: profileImageProvider(
                  _preferences['profileAvatar'] as String? ?? '',
                ),
                child:
                    profileImageProvider(
                          _preferences['profileAvatar'] as String? ?? '',
                        ) ==
                        null
                    ? Text(
                        _profileName.text.trim().isEmpty
                            ? 'A'
                            : _profileName.text
                                  .trim()
                                  .substring(0, 1)
                                  .toUpperCase(),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Set the assistant’s display name, photo, persona, and starting context.',
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _chooseProfilePhoto,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose AI profile photo'),
              ),
              TextButton(
                onPressed: _removeProfilePhoto,
                child: const Text('Remove photo'),
              ),
            ],
          ),
          if (_profilePhotoError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _profilePhotoError,
                style: const TextStyle(color: Color(0xffa84e3b), fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _profileAvatar,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (value) => _updateProfile('profileAvatar', value),
            decoration: const InputDecoration(
              labelText: 'AI profile photo URL',
              hintText: 'https://example.com/photo.png',
              prefixIcon: Icon(Icons.account_circle_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _profileName,
            maxLength: 48,
            onChanged: (value) => _updateProfile('profileName', value),
            decoration: const InputDecoration(
              labelText: 'AI display name',
              hintText: 'Name shown for the assistant',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _profilePersona,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            onChanged: (value) => _updateProfile('profilePersona', value),
            decoration: const InputDecoration(
              labelText: 'Assistant persona',
              hintText: 'Describe the assistant’s personality and style.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _profileContext,
            maxLength: 4000,
            minLines: 3,
            maxLines: 6,
            onChanged: (value) => _updateProfile('profileContext', value),
            decoration: const InputDecoration(
              labelText: 'Initial context for the assistant',
              hintText:
                  'Background context that should guide the assistant between chats.',
              alignLabelWithHint: true,
            ),
          ),
          Text(
            'The AI profile stays on this device. Its name, persona, and context are sent with chat requests; its photo is not.',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          const _SectionHeader(label: 'GENERAL'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Assistant name'),
            subtitle: const Text('Choose the name shown in chats.'),
            trailing: SizedBox(
              width: 135,
              child: TextField(
                textAlign: TextAlign.end,
                maxLength: 32,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                controller: _name,
                onChanged: (value) async {
                  _preferences['assistantName'] = value;
                  await widget.onSave(Map<String, dynamic>.from(_preferences));
                },
                decoration: const InputDecoration(
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          if (_models.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ollama model'),
              subtitle: const Text('Switch the model used by the server.'),
              trailing: DropdownButton<String>(
                value: _models.contains(_selectedModel) ? _selectedModel : null,
                hint: const Text('Select'),
                onChanged: _saving ? null : _changeModel,
                items: _models
                    .map(
                      (model) =>
                          DropdownMenuItem(value: model, child: Text(model)),
                    )
                    .toList(),
              ),
            ),
          _ToggleSetting(
            title: 'Web search',
            subtitle:
                'Search when you ask or when answers need current information.',
            value: _preferences['webSearchEnabled'] == true,
            onChanged: (value) => _updatePreference('webSearchEnabled', value),
          ),
          _ToggleSetting(
            title: 'Image search',
            subtitle:
                'Search for images when you ask for pictures or visual examples.',
            value: _preferences['imageSearchEnabled'] == true,
            onChanged: (value) =>
                _updatePreference('imageSearchEnabled', value),
          ),
          _ToggleSetting(
            title: 'Dark mode',
            subtitle: 'Use the dark chat theme.',
            value: dark,
            onChanged: (value) => _updatePreference('darkModeEnabled', value),
          ),
          const SizedBox(height: 10),
          Text(
            'Search sends relevant prompts to external search providers. Preferences and chat history are saved on this device.',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label,
      style: TextStyle(
        color: appAccent(context),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );
}

class _ToggleSetting extends StatelessWidget {
  const _ToggleSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, height: 1.4)),
    value: value,
    activeTrackColor: appAccent(context),
    onChanged: onChanged,
  );
}
