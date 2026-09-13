import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/models/member.dart';
import '../../core/models/task_request.dart';

/// Section 4.3 — the pending-approvals queue.
///
/// What appears here is exactly what this person is entitled to action: a Lead
/// sees their own department's Members, the President sees Leads and the
/// executive tier, a Director sees everything and can unblock a stuck queue.
/// The filtering is the server's, not ours.
class ApprovalsPage extends StatelessWidget {
  const ApprovalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final gutter = GwdSpace.gutter(MediaQuery.sizeOf(context).width);
    final requests = store.pendingApprovals;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      appBar: AppBar(
        title: Text('Approvals',
            style: GwdType.title3.copyWith(color: GwdColors.inkOf(context))),
      ),
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadPendingApprovals(),
        child: requests.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.how_to_reg_outlined,
                    title: 'Nobody waiting',
                    message:
                        'When someone requests access to your department, they appear here for you to approve.',
                  ),
                ],
              )
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(gutter, GwdSpace.lg, gutter, GwdSpace.xxxl),
                itemCount: requests.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: GwdSpace.md),
                  child: AppleStaggerItem(
                    index: i,
                    child: _ApprovalCard(
                      key: ValueKey(requests[i].id),
                      request: requests[i],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({super.key, required this.request});
  final AccessRequest request;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    try {
      await AppScope.readStore(context).decideAccess(widget.request.id, approve: approve);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final color = request.applicantColor != null &&
            request.applicantColor!.startsWith('#') &&
            request.applicantColor!.length == 7
        ? Color(int.parse('FF${request.applicantColor!.substring(1)}', radix: 16))
        : GwdColors.inkTertiaryOf(context);

    return SurfaceCard(
      emphasis: SurfaceEmphasis.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(initials: request.initials, tint: color, size: 44),
              const SizedBox(width: GwdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.applicantNeedsName ? 'No name yet' : request.applicantName,
                      style: GwdType.headline.copyWith(
                        color: request.applicantNeedsName
                            ? GwdColors.inkTertiaryOf(context)
                            : GwdColors.inkOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // What they are asking to be, and where — "Marketing
                      // Lead", the same phrasing the club will use for them
                      // once they are in.
                      positionLineFor(request.requestedRole, request.departmentName),
                      style: GwdType.footnote
                          .copyWith(color: GwdColors.inkTertiaryOf(context)),
                    ),
                  ],
                ),
              ),
              RoleBadge(role: request.requestedRole, dense: true),
            ],
          ),

          // A seeded Lead account has no name on it. Whoever hands the
          // credentials over knows whose account it is, and this is the moment
          // they have it in front of them — approving first means the club
          // carries an account called "Creative Lead" until its holder
          // eventually signs in.
          if (request.applicantNeedsName) ...[
            const SizedBox(height: GwdSpace.md),
            _NameThisAccount(
              userId: request.userId,
              hint: request.departmentName,
              enabled: !_busy,
            ),
          ],

          if (request.applicantEmail.isNotEmpty || request.applicantPhone.isNotEmpty) ...[
            const SizedBox(height: GwdSpace.md),
            Container(
              padding: const EdgeInsets.all(GwdSpace.md),
              decoration: BoxDecoration(
                color: GwdColors.sunkenOf(context),
                borderRadius: BorderRadius.circular(GwdRadius.md),
              ),
              child: Column(
                children: [
                  if (request.applicantEmail.isNotEmpty)
                    _detail(context, Icons.mail_outline_rounded, request.applicantEmail),
                  if (request.applicantPhone.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _detail(context, Icons.phone_outlined, request.applicantPhone),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: GwdSpace.lg),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Approve',
                  busy: _busy,
                  icon: Icons.check_rounded,
                  onPressed: () => _decide(true),
                ),
              ),
              const SizedBox(width: GwdSpace.md),
              SecondaryButton(
                label: 'Decline',
                destructive: true,
                onPressed: _busy ? null : () => _decide(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(BuildContext context, IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 13, color: GwdColors.inkTertiaryOf(context)),
        const SizedBox(width: GwdSpace.sm),
        Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context))),
        ),
      ],
    );
  }
}

/// Put a name on an account that arrived without one.
///
/// Inline rather than a sheet: it is one field, and the person approving is
/// already looking at the card. A sheet for a single text box is a tap and a
/// dismissal for nothing.
class _NameThisAccount extends StatefulWidget {
  const _NameThisAccount({
    required this.userId,
    required this.enabled,
    this.hint,
  });

  final String userId;
  final bool enabled;
  final String? hint;

  @override
  State<_NameThisAccount> createState() => _NameThisAccountState();
}

class _NameThisAccountState extends State<_NameThisAccount> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = AppScope.readStore(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await store.renameMember(widget.userId, _name.text.trim());
      messenger.showSnackBar(
        SnackBar(content: Text('Named ${_name.text.trim()}.')),
      );
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().length >= 2;
    return Container(
      padding: const EdgeInsets.all(GwdSpace.md),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
        border: Border.all(color: GwdColors.primaryRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.hint == null
                ? 'This account was created before anyone held it.'
                : 'Who is taking ${widget.hint}?',
            style: GwdType.footnote
                .copyWith(color: GwdColors.inkSecondaryOf(context)),
          ),
          const SizedBox(height: GwdSpace.sm),
          Row(
            children: [
              Expanded(
                child: GwdField(
                  label: 'Their name',
                  controller: _name,
                  enabled: widget.enabled && !_busy,
                  hint: 'Full name',
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (valid) _save();
                  },
                ),
              ),
              const SizedBox(width: GwdSpace.sm),
              Padding(
                // Nudge down past the field's own label so the two line up.
                padding: const EdgeInsets.only(top: GwdSpace.lg),
                child: SecondaryButton(
                  label: 'Save',
                  onPressed: valid && widget.enabled && !_busy ? _save : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
