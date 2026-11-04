import 'package:flutter/material.dart';
import 'package:vertree/modules/conversion/conversion.dart';

class ConversionFormatPicker extends StatefulWidget {
  const ConversionFormatPicker({super.key, required this.formats});
  final List<ConversionFormat> formats;
  @override
  State<ConversionFormatPicker> createState() => _ConversionFormatPickerState();
}

class _ConversionFormatPickerState extends State<ConversionFormatPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final visible = widget.formats
        .where(
          (format) =>
              format.name.toLowerCase().contains(_query) ||
              format.id.contains(_query) ||
              format.description.contains(_query),
        )
        .toList();
    return Dialog(
      child: SizedBox(
        width: 440,
        height: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择目标格式',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索格式',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('没有匹配的格式'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final format = visible[index];
                          return ListTile(
                            title: Text(format.name),
                            trailing: Text('.${format.id}'),
                            onTap: () => Navigator.pop(context, format),
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
