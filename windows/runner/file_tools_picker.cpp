#include "file_tools_picker.h"
#include "file_tools_picker_native.h"
#include <shlobj.h>

namespace {
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
using Microsoft::WRL::ComPtr;

std::wstring Label(const EncodableMap* values, const char* key, const wchar_t* fallback) {
  if (!values) return fallback;
  const auto it = values->find(EncodableValue(key));
  if (it == values->end()) return fallback;
  const auto* text = std::get_if<std::string>(&it->second);
  if (!text || text->empty() || text->size() > 32768) return fallback;
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(),
      static_cast<int>(text->size()), nullptr, 0);
  if (!length) return fallback;
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(),
      static_cast<int>(text->size()), result.data(), length);
  return result;
}

HRESULT Pick(HWND owner, const EncodableMap* arguments, EncodableList& result) {
  ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&dialog));
  if (FAILED(hr)) return hr;
  DWORD options = 0;
  hr = dialog->GetOptions(&options);
  if (SUCCEEDED(hr)) hr = dialog->SetOptions(options | FOS_FORCEFILESYSTEM |
      FOS_ALLOWMULTISELECT | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST |
      FOS_NODEREFERENCELINKS | FOS_DONTADDTORECENT);
  if (FAILED(hr)) return hr;
  const auto title = Label(arguments, "title", L"Choose files or folders");
  const auto choose = Label(arguments, "selectLabel", L"Choose selected items");
  const auto folder = Label(arguments, "folderLabel", L"Choose this folder");
  const auto hint = Label(arguments, "hint", L"Select files and folders together; double-click a folder to browse.");
  dialog->SetTitle(title.c_str());
  const auto initial = Label(arguments, "initialDirectory", L"");
  if (!initial.empty()) {
    ComPtr<IShellItem> item;
    if (SUCCEEDED(SHCreateItemFromParsingName(initial.c_str(), nullptr, IID_PPV_ARGS(&item))))
      dialog->SetFolder(item.Get());
  }
  ComPtr<IFileDialogCustomize> custom;
  hr = dialog.As(&custom);
  if (FAILED(hr)) return hr;
  hr = custom->AddPushButton(vertree_picker::kChoose, folder.c_str());
  if (FAILED(hr)) return hr;
  custom->MakeProminent(vertree_picker::kChoose);
  custom->AddText(vertree_picker::kHint, hint.c_str());
  ComPtr<vertree_picker::SelectionEvents> events;
  events.Attach(new vertree_picker::SelectionEvents(dialog.Get(), choose, folder));
  DWORD cookie = 0;
  hr = dialog->Advise(events.Get(), &cookie);
  if (FAILED(hr)) return hr;
  hr = dialog->Show(owner);
  dialog->Unadvise(cookie);
  if (FAILED(hr)) return hr;
  if (!events->customSelection) {
    ComPtr<IShellItemArray> items;
    hr = dialog->GetResults(&items);
    if (SUCCEEDED(hr)) hr = vertree_picker::ReadTargets(items.Get(), events->selected);
    if (FAILED(hr)) return hr;
  }
  for (const auto& path : events->selected) {
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.data(),
        static_cast<int>(path.size()), nullptr, 0, nullptr, nullptr);
    if (!size) return HRESULT_FROM_WIN32(GetLastError());
    std::string utf8(size, '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.data(),
        static_cast<int>(path.size()), utf8.data(), size, nullptr, nullptr);
    result.emplace_back(utf8);
  }
  return S_OK;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>>
RegisterFileToolsPicker(flutter::BinaryMessenger* messenger, HWND owner) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "vertree/file-tools-picker", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([owner, open = false](const auto& call, auto result) mutable {
    if (call.method_name() != "pickItems") { result->NotImplemented(); return; }
    if (open) { result->Error("PICKER_BUSY", "A selection dialog is already open."); return; }
    open = true;
    const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
    EncodableList selected;
    const auto hr = Pick(owner, args, selected);
    open = false;
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      result->Success();
    } else if (FAILED(hr)) {
      result->Error("PICKER_FAILED", "Could not select filesystem items (HRESULT " +
          std::to_string(static_cast<unsigned long>(hr)) + ").");
    } else {
      result->Success(EncodableValue(selected));
    }
  });
  return channel;
}
