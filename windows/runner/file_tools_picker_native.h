#pragma once
#include <windows.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <string>
#include <vector>

namespace vertree_picker {
using Microsoft::WRL::ComPtr;
constexpr DWORD kChoose = 4101;
constexpr DWORD kHint = 4102;
constexpr size_t kMaxTargets = 1024;
constexpr size_t kMaxCharacters = 512 * 1024;

inline HRESULT ReadTargets(IShellItemArray* items, std::vector<std::wstring>& paths) {
  if (!items) return E_INVALIDARG;
  DWORD count = 0;
  HRESULT hr = items->GetCount(&count);
  if (FAILED(hr)) return hr;
  if (count == 0 || count > kMaxTargets) return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
  std::vector<std::wstring> selected;
  size_t characters = 0;
  for (DWORD index = 0; index < count; ++index) {
    ComPtr<IShellItem> item;
    hr = items->GetItemAt(index, &item);
    if (FAILED(hr)) return hr;
    PWSTR value = nullptr;
    hr = item->GetDisplayName(SIGDN_FILESYSPATH, &value);
    if (FAILED(hr)) return hr;
    std::wstring path(value ? value : L"");
    CoTaskMemFree(value);
    characters += path.size();
    if (path.empty() || path.size() > 32767 || characters > kMaxCharacters)
      return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
    selected.push_back(std::move(path));
  }
  paths = std::move(selected);
  return S_OK;
}

class SelectionEvents final : public IFileDialogEvents, public IFileDialogControlEvents {
 public:
  SelectionEvents(IFileOpenDialog* dialog, std::wstring choose, std::wstring folder)
      : dialog_(dialog), choose_(std::move(choose)), folder_(std::move(folder)) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (id == IID_IUnknown || id == IID_IFileDialogEvents)
      *out = static_cast<IFileDialogEvents*>(this);
    else if (id == IID_IFileDialogControlEvents)
      *out = static_cast<IFileDialogControlEvents*>(this);
    else return E_NOINTERFACE;
    AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs_); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto count = InterlockedDecrement(&refs_);
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE OnFileOk(IFileDialog*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnFolderChanging(IFileDialog*, IShellItem*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnFolderChange(IFileDialog*) override { UpdateLabel(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnSelectionChange(IFileDialog*) override { UpdateLabel(); return S_OK; }
  HRESULT STDMETHODCALLTYPE OnShareViolation(IFileDialog*, IShellItem*, FDE_SHAREVIOLATION_RESPONSE* response) override {
    if (response) *response = FDESVR_DEFAULT;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnTypeChange(IFileDialog*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnOverwrite(IFileDialog*, IShellItem*, FDE_OVERWRITE_RESPONSE* response) override {
    if (response) *response = FDEOR_DEFAULT;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnItemSelected(IFileDialogCustomize*, DWORD, DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnCheckButtonToggled(IFileDialogCustomize*, DWORD, BOOL) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnControlActivating(IFileDialogCustomize*, DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnButtonClicked(IFileDialogCustomize*, DWORD id) override {
    if (id != kChoose) return S_OK;
    ComPtr<IShellItemArray> items;
    DWORD count = 0;
    HRESULT hr = dialog_->GetSelectedItems(&items);
    if (SUCCEEDED(hr) && items) hr = items->GetCount(&count);
    if (FAILED(hr) || count == 0) {
      // No selection: the button explicitly reads "Choose this folder".
      ComPtr<IShellItem> folder;
      hr = dialog_->GetFolder(&folder);
      if (SUCCEEDED(hr)) {
        items.Reset();
        hr = SHCreateShellItemArrayFromShellItem(folder.Get(), IID_PPV_ARGS(&items));
      }
    }
    if (SUCCEEDED(hr)) hr = ReadTargets(items.Get(), selected);
    selectionError = hr;
    if (SUCCEEDED(hr)) customSelection = true;
    // Close does not provide GetResults: the selected paths above are retained.
    dialog_->Close(hr);
    return S_OK;
  }
  bool customSelection = false;
  HRESULT selectionError = S_OK;
  std::vector<std::wstring> selected;
 private:
  void UpdateLabel() {
    ComPtr<IFileDialogCustomize> custom;
    if (FAILED(dialog_->QueryInterface(IID_PPV_ARGS(&custom)))) return;
    ComPtr<IShellItemArray> items;
    DWORD count = 0;
    if (SUCCEEDED(dialog_->GetSelectedItems(&items)) && items) items->GetCount(&count);
    custom->SetControlLabel(kChoose, count ? choose_.c_str() : folder_.c_str());
  }
  LONG refs_ = 1;
  IFileOpenDialog* dialog_; // dialog outlives Advise/Unadvise; no COM cycle.
  std::wstring choose_, folder_;
};
}  // namespace vertree_picker
