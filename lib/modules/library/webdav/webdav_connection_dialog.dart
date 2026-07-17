import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/form/text_form_field.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/controllers/use_shadcn_text_editing_controller.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/services/webdav/webdav_client.dart';
import 'package:spotube/utils/platform.dart';
import 'package:uuid/uuid.dart';

class WebDavConnectionDialog extends HookConsumerWidget {
  final WebDavAccount? account;

  const WebDavConnectionDialog({super.key, this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(() => GlobalKey<FormBuilderState>(), []);
    final nameController = useShadcnTextEditingController(text: account?.name);
    final urlController = useShadcnTextEditingController(text: account?.url);
    final rootPathController = useShadcnTextEditingController(
      text: account?.rootPath,
    );
    final usernameController =
        useShadcnTextEditingController(text: account?.username);
    final passwordController =
        useShadcnTextEditingController(text: account?.password);
    final busy = useState(false);
    final status = useState<(String, bool)?>(null);
    final compactActions = kIsMobile && MediaQuery.sizeOf(context).width < 480;
    final availableHeight = (MediaQuery.sizeOf(context).height -
            MediaQuery.viewPaddingOf(context).vertical -
            MediaQuery.viewInsetsOf(context).bottom -
            48)
        .clamp(280.0, 680.0)
        .toDouble();

    WebDavAccount? createAccount() {
      if (formKey.currentState?.saveAndValidate() != true) return null;
      final normalizedUrl = WebDavAccount.normalizeUri(urlController.text);
      final normalizedRootPath = WebDavAccount.normalizeRootPath(
        rootPathController.text,
      );
      return WebDavAccount(
        id: account?.id ?? const Uuid().v4(),
        name: nameController.text.trim(),
        url: normalizedUrl.toString(),
        rootPath: normalizedRootPath,
        username: usernameController.text.trim(),
        password: passwordController.text,
      );
    }

    Future<void> connect({required bool save}) async {
      WebDavAccount? value;
      try {
        value = createAccount();
      } on FormatException {
        formKey.currentState?.fields['url']?.invalidate(
          context.l10n.webdav_invalid_url,
        );
      }
      if (value == null) return;

      busy.value = true;
      status.value = null;
      final client = WebDavClient(value);
      try {
        final connectedRoot = await client.testConnection();
        if (!context.mounted) return;
        if (connectedRoot != value.endpointUri) {
          value = value.copyWith(url: connectedRoot.toString());
          urlController.text = connectedRoot.toString();
        }
        status.value = (context.l10n.webdav_connection_successful, true);
        if (save) Navigator.of(context).pop(value);
      } on WebDavException catch (error) {
        if (!context.mounted) return;
        status.value = (
          error.statusCode == 401 || error.statusCode == 403
              ? context.l10n.webdav_authentication_failed
              : error.message,
          false,
        );
      } finally {
        client.close();
        if (context.mounted) busy.value = false;
      }
    }

    final cancelButton = Button.outline(
      onPressed: busy.value ? null : () => Navigator.of(context).pop(),
      child: Text(context.l10n.cancel),
    );
    final testButton = Button.secondary(
      onPressed: busy.value ? null : () => connect(save: false),
      child: busy.value
          ? const CircularProgressIndicator()
          : Text(context.l10n.test_connection),
    );
    final saveButton = Button.primary(
      onPressed: busy.value ? null : () => connect(save: true),
      child: Text(context.l10n.save),
    );

    final alert = Alert(
      title: Text(
        account == null
            ? context.l10n.connect_webdav
            : context.l10n.edit_webdav,
      ).h4(),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: availableHeight,
        ),
        child: SingleChildScrollView(
          child: FormBuilder(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                TextFormBuilderField(
                  name: 'name',
                  controller: nameController,
                  label: Text(context.l10n.webdav_name),
                  placeholder: Text(context.l10n.webdav_name_hint),
                  validator: FormBuilderValidators.required(),
                  enabled: !busy.value,
                ),
                TextFormBuilderField(
                  name: 'url',
                  controller: urlController,
                  label: Text(context.l10n.webdav_url),
                  placeholder: Text(context.l10n.webdav_url_hint),
                  keyboardType: TextInputType.url,
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    (value) {
                      try {
                        WebDavAccount.normalizeUri(value ?? '');
                        return null;
                      } on FormatException {
                        return context.l10n.webdav_invalid_url;
                      }
                    },
                  ]),
                  enabled: !busy.value,
                ),
                TextFormBuilderField(
                  name: 'rootPath',
                  controller: rootPathController,
                  label: Text(context.l10n.webdav_folder),
                  placeholder: Text(context.l10n.webdav_folder_hint),
                  validator: (value) {
                    try {
                      WebDavAccount.normalizeRootPath(value ?? '');
                      return null;
                    } on FormatException {
                      return context.l10n.webdav_invalid_folder;
                    }
                  },
                  enabled: !busy.value,
                ),
                TextFormBuilderField(
                  name: 'username',
                  controller: usernameController,
                  label: Text(context.l10n.webdav_username),
                  placeholder: Text(context.l10n.webdav_username),
                  autofillHints: const [AutofillHints.username],
                  enabled: !busy.value,
                ),
                TextFormBuilderField(
                  name: 'password',
                  controller: passwordController,
                  label: Text(context.l10n.webdav_password),
                  placeholder: Text(context.l10n.webdav_password_hint),
                  obscureText: true,
                  features: const [InputFeature.passwordToggle()],
                  autofillHints: const [AutofillHints.password],
                  enabled: !busy.value,
                ),
                if (status.value case (final message, final success))
                  Text(
                    message,
                    style: TextStyle(
                      color: success ? Colors.green : Colors.red,
                    ),
                  ),
                if (compactActions)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [testButton, saveButton, cancelButton],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: cancelButton),
                      const Gap(8),
                      Expanded(child: testButton),
                      const Gap(8),
                      Expanded(child: saveButton),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!kIsMobile) return alert;
    return SafeArea(
      minimum: const EdgeInsets.all(12),
      child: alert,
    );
  }
}
