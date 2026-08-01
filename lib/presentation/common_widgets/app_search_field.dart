import 'package:flutter/material.dart';

/// Champ de recherche standard (icone loupe + placeholder), utilise sur
/// Ventes/Produits/Rapports. Nomme "AppSearchField" (plutot que "SearchBar")
/// pour ne pas entrer en collision avec le widget Material 3 SearchBar.
class AppSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const AppSearchField({
    super.key,
    this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
      ),
    );
  }
}
