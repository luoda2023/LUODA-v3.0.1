part of 'desktop_setting_page.dart';

class _Account extends StatefulWidget {
  const _Account({Key? key}) : super(key: key);

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        _Card(
          title: 'Account',
          children: kLocalProfileOnly
              ? [
                  ListTile(
                    leading: const Icon(
                      Icons.person_outline_rounded,
                      color: _accentColor,
                    ),
                    title: Text(translate('Local profile only')),
                    subtitle: Text(translate(
                      'DotChat stores the name, avatar, contacts, and pairing data on this device only.',
                    )),
                  ),
                ]
              : [accountAction(), useInfo()],
        ),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget accountAction() {
    return Obx(() => _Button(
        gFFI.userModel.userName.value.isEmpty
            ? 'Login'
            : '${translate('Logout')} (${gFFI.userModel.accountLabelWithHandle})',
        () => {
              gFFI.userModel.userName.value.isEmpty
                  ? loginDialog()
                  : logOutConfirmDialog()
            },
        icon: gFFI.userModel.userName.value.isEmpty
            ? Icons.login
            : Icons.logout));
  }

  Widget useInfo() {
    return Obx(() => Offstage(
          offstage: gFFI.userModel.userName.value.isEmpty,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Builder(builder: (context) {
              final avatarWidget = _buildUserAvatar();
              return Row(
                children: [
                  if (avatarWidget != null) avatarWidget,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gFFI.userModel.displayNameOrUserName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectionArea(
                          child: Text(
                            '@${gFFI.userModel.userName.value}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        )).marginOnly(left: 18, top: 16);
  }

  Widget? _buildUserAvatar() {
    // Resolve relative avatar path at display time
    final avatar =
        bind.mainResolveAvatarUrl(avatar: gFFI.userModel.avatar.value);
    return buildAvatarWidget(
      avatar: avatar,
      size: 44,
    );
  }
}
