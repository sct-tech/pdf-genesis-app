import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/router/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/document.dart';
import '../data/documents_repository.dart';
import 'document_widgets.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  DocumentsQuery _query = const DocumentsQuery();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = _query.copyWith(search: value.trim()));
    });
  }

  void _toggleSort() {
    setState(() {
      _query = _query.copyWith(
        sort: _query.sort == DocumentSort.newest
            ? DocumentSort.oldest
            : DocumentSort.newest,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsListProvider(_query));
    final text = Theme.of(context).textTheme;
    final anyInProgress =
        documents.value?.any((document) => document.isInProgress) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(
              child: Text('Documents', overflow: TextOverflow.ellipsis),
            ),
            if (documents.hasValue && documents.value!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Pill(
                label: '${documents.value!.length}',
                foreground: AppColors.primary,
                background: AppColors.primaryTint,
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.upload),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Upload PDF'),
      ),
      body: ContentWidth(
        maxWidth: ContentWidths.wide,
        child: PollWhile(
          active: anyInProgress,
          onTick: () => ref.invalidate(documentsListProvider(_query)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search documents',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    onPressed: _toggleSort,
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    shape: const StadiumBorder(),
                    avatar: const Icon(Icons.swap_vert_rounded, size: 18),
                    label: Text(
                      _query.sort == DocumentSort.newest
                          ? 'Sort: Newest first'
                          : 'Sort: Oldest first',
                      style: text.labelMedium,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: documents.when(
                  skipLoadingOnRefresh: true,
                  skipLoadingOnReload: true,
                  loading: () => const LoadingView(),
                  error: (error, _) => MessageView.error(
                    message: errorMessage(error),
                    onRetry: () =>
                        ref.invalidate(documentsListProvider(_query)),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return _query.search.isEmpty
                          ? MessageView(
                              icon: Icons.upload_file_rounded,
                              title: 'No documents yet',
                              message: 'Upload a PDF to summarise it and ask questions.',
                              actionLabel: 'Upload PDF',
                              onAction: () => context.push(Routes.upload),
                            )
                          : MessageView(
                              icon: Icons.search_off_rounded,
                              title: 'No matches',
                              message:
                                  'No document title contains "${_query.search}".',
                            );
                    }
                    return RefreshIndicator(
                      onRefresh: () =>
                          ref.refresh(documentsListProvider(_query).future),
                      // An account holds a handful of documents, so the list
                      // does not need to be lazy
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        children: [
                          AdaptiveGrid(
                            spacing: 10,
                            children: [
                              for (final document in items)
                                _DocumentRow(document: document),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentRow extends ConsumerWidget {
  const _DocumentRow({required this.document});

  final Document document;

  void _open(BuildContext context) {
    context.push(
      document.isInProgress
          ? Routes.processing(document.id)
          : Routes.document(document.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      onTap: () => _open(context),
      child: Row(
        children: [
          const PdfTile(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  documentMeta(document),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(status: document.status),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'open') {
                _open(context);
              } else if (value == 'view') {
                context.push(Routes.viewer(document.id));
              } else {
                deleteDocumentFlow(context, ref, document);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'open',
                child: ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('Open'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'view',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('View & Edit PDF'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
