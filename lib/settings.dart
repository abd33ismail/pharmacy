import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings'.tr()),
        centerTitle: true,
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: Text('language'.tr()),
            leading: const Icon(Icons.language),
            onTap: () {
              // Show language selection dialog
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text('select_language'.tr()),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ListTile(
                          title: const Text('English'),
                          onTap: () {
                            context.setLocale(const Locale('en'));
                            Navigator.of(context).pop();
                          },
                        ),
                        ListTile(
                          title: const Text('العربية'),
                          onTap: () {
                            context.setLocale(const Locale('ar'));
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const Divider(),
          ListTile(
            title: Text('about_us'.tr()),
            leading: const Icon(Icons.info),
            onTap: () {
              // Navigate to about us page
            },
          ),
        ],
      ),
    );
  }
}
