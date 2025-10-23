import 'package:aradia/resources/designs/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import '../../../resources/designs/app_colors.dart';
import '../../../resources/models/character.dart';
import '../../../resources/services/character_service.dart';

class CharactersDialog extends StatefulWidget {
  final String audiobookId;

  const CharactersDialog({super.key, required this.audiobookId});

  @override
  State<CharactersDialog> createState() => _CharactersDialogState();
}

class _CharactersDialogState extends State<CharactersDialog> {
  final CharacterService _characterService = CharacterService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  List<Character> _characters = [];
  List<Character> _filteredCharacters = [];
  bool _isLoading = false;
  bool _isSearching = false;
  int? _selectedIndex;
  Character? _editingCharacter;

  @override
  void initState() {
    super.initState();
    _initializeService();
    _searchController.addListener(_filterCharacters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    await _characterService.init();
    _loadCharacters();
  }

  void _loadCharacters() {
    setState(() {
      _isLoading = true;
    });

    _characters =
        _characterService.getAllCharacters(audiobookId: widget.audiobookId);
    _filteredCharacters = List.from(_characters);

    setState(() {
      _isLoading = false;
    });
  }

  void _filterCharacters() {
    final query = _searchController.text;
    setState(() {
      _filteredCharacters = _characterService.searchCharacters(query,
          audiobookId: widget.audiobookId);
      _selectedIndex = null; // Deselect when filtering
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredCharacters = List.from(_characters);
      }
    });
  }

  void _selectCharacter(int index) {
    setState(() {
      _selectedIndex = _selectedIndex == index ? null : index;
    });
  }

  void _deselectCharacter() {
    setState(() {
      _selectedIndex = null;
    });
  }

  void _reorderCharacters(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final Character item = _filteredCharacters.removeAt(oldIndex);
      _filteredCharacters.insert(newIndex, item);

      // Update the main list as well
      _characters = List.from(_filteredCharacters);
      // Update selected index if needed
      if (_selectedIndex == oldIndex) {
        _selectedIndex = newIndex;
      }
    });
  }

  Future<void> _showAddEditDialog({Character? character}) async {
    _editingCharacter = character;
    _nameController.text = character?.name ?? '';
    _descriptionController.text = character?.description ?? '';

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(character == null ? 'Add Character' : 'Edit Character'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              _saveCharacter();
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCharacter() async {
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty) return;

    if (_editingCharacter == null) {
      // Add new character
      final character = Character(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        audiobookId: widget.audiobookId,
        name: name,
        description: description,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _characterService.addCharacter(character);
    } else {
      // Update existing character
      final updatedCharacter = _editingCharacter!.copyWith(
        name: name,
        description: description,
        updatedAt: DateTime.now(),
      );
      await _characterService.updateCharacter(updatedCharacter);
    }

    _nameController.clear();
    _descriptionController.clear();
    _loadCharacters();
  }

  Future<void> _deleteCharacter(Character character) async {
    await _characterService.deleteCharacter(character.id);
    _deselectCharacter();
    _loadCharacters();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCharacter =
        _selectedIndex != null ? _filteredCharacters[_selectedIndex!] : null;
    final ThemeNotifier themeNotifier =
        Provider.of<ThemeNotifier>(context, listen: false);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          children: [
            // Header or Contextual Action Bar
            _selectedIndex == null
                ? _buildDefaultHeader(isDark)
                : _buildContextualActionBar(isDark, selectedCharacter!),

            // Search field (only visible when searching)
            if (_isSearching) _buildSearchField(isDark),

            // Character List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildCharacterList(isDark),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeNotifier.themeMode == ThemeMode.dark
                    ? Colors.black.withValues(alpha: 0.1)
                    : Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_characters.length} Characters',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardColor : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.dividerColor : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.people, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Text(
            'Characters',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _isSearching ? Ionicons.close : Ionicons.search,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            onPressed: _toggleSearch,
            tooltip: _isSearching ? 'Close Search' : 'Search',
          ),
          IconButton(
            icon: Icon(
              Icons.add,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            onPressed: () => _showAddEditDialog(),
            tooltip: 'Add Character',
          ),
        ],
      ),
    );
  }

  Widget _buildContextualActionBar(bool isDark, Character character) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.cardColor
            : AppColors.primaryColor.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.dividerColor
                : AppColors.primaryColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              character.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.primaryColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.edit,
              color: isDark ? Colors.white70 : AppColors.primaryColor,
            ),
            onPressed: () => _showAddEditDialog(character: character),
            tooltip: 'Edit',
          ),
          IconButton(
            icon: Icon(
              Ionicons.trash_outline,
              color: isDark ? Colors.red.shade300 : Colors.red,
            ),
            onPressed: () {
              _deleteCharacter(character);
            },
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardColor : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.dividerColor : Colors.grey.shade300,
          ),
        ),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search characters...',
          prefixIcon: const Icon(Ionicons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCharacterList(bool isDark) {
    if (_filteredCharacters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Ionicons.people_outline,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              _isSearching ? 'No characters found' : 'No characters yet',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            if (!_isSearching) ...[
              const SizedBox(height: 8),
              Text(
                'Tap the + icon to add a character',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      itemCount: _filteredCharacters.length,
      onReorder: _reorderCharacters,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final character = _filteredCharacters[index];
        final isSelected = _selectedIndex == index;

        return Material(
          key: ValueKey(character.id),
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectCharacter(index),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                        ? AppColors.primaryColor.withValues(alpha: 0.2)
                        : AppColors.primaryColor.withValues(alpha: 0.1))
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color:
                        isDark ? AppColors.dividerColor : Colors.grey.shade200,
                  ),
                ),
              ),
              child: ListTile(
                leading: ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Ionicons.reorder_two,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                ),
                title: Text(
                  character.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: character.description.isNotEmpty
                    ? Text(
                        character.description,
                        //maxLines: 5, // need to decide
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      )
                    : null,
                trailing: isSelected
                    ? Icon(
                        Ionicons.checkmark_circle,
                        color: isDark
                            ? AppColors.primaryColor
                            : AppColors.primaryColor,
                      )
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
