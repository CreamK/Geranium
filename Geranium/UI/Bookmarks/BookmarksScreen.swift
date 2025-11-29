//
//  BookmarksScreen.swift
//  Geranium
//
//  Created by Codex on 22.05.2024.
//

import SwiftUI
import UniformTypeIdentifiers

struct BookmarksScreen: View {
    @ObservedObject var viewModel: BookmarksViewModel
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    #if os(macOS)
    @State private var importFileURL: URL?
    #endif

    var body: some View {
        Group {
            if #available(iOS 16.0, macOS 13.0, *) {
                NavigationStack {
                    bookmarksList
                }
            } else {
                NavigationView {
                    bookmarksList
                }
            }
        }
        .sheet(item: $viewModel.editorMode) { mode in
            BookmarkEditorView(mode: mode, onSave: { name, coordinate, note in
                viewModel.saveBookmark(name: name, coordinate: coordinate, note: note)
            }, onCancel: {
                viewModel.dismissEditor()
            })
        }
        .confirmationDialog(
            "检测到旧版 LocSim 收藏，是否导入？",
            isPresented: $viewModel.showImportPrompt,
            titleVisibility: .visible
        ) {
            Button("导入", action: viewModel.performLegacyImport)
            Button("取消", role: .cancel) {}
        }
        .alert(isPresented: $viewModel.showImportResult) {
            Alert(title: Text("导入结果"),
                  message: Text(viewModel.importResultMessage ?? ""),
                  dismissButton: .default(Text("确定")))
        }
        #if os(macOS)
        .fileImporter(
            isPresented: $viewModel.showImportFilePicker,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.importBookmarks(from: url)
                }
            case .failure:
                viewModel.importResultMessage = "选择文件失败。"
                viewModel.showImportResult = true
            }
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let items = viewModel.shareSheetItems {
                ShareSheet(items: items, isPresented: $viewModel.showShareSheet)
            }
        }
        #else
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let items = viewModel.shareSheetItems {
                ShareSheet(items: items, isPresented: $viewModel.showShareSheet)
            }
        }
        .sheet(isPresented: $viewModel.showImportFilePicker) {
            DocumentPicker(contentTypes: [UTType.json]) { urls in
                if let url = urls.first {
                    viewModel.importBookmarks(from: url)
                }
            }
        }
        #endif
        .onAppear {
            viewModel.evaluateLegacyState()
        }
    }

    private var bookmarksList: some View {
        List {
            Section {
                if bookmarkStore.bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("暂无收藏")
                            .font(.headline)
                        Text("在地图上放置定位点或使用右上角的 + 号即可保存常用位置。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        BookmarkCardView(bookmark: bookmark,
                                         isActive: bookmark.id == bookmarkStore.lastUsedBookmarkID,
                                         action: {
                            viewModel.select(bookmark)
                        })
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.delete(bookmark)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }

                            Button {
                                viewModel.edit(bookmark)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove(perform: viewModel.moveBookmarks)
                    .onDelete(perform: viewModel.deleteBookmarks)
                }
            } header: {
                Text("收藏的地点")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("收藏")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !bookmarkStore.bookmarks.isEmpty {
                    EditButton()
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    if !bookmarkStore.bookmarks.isEmpty {
                        Button(action: viewModel.shareBookmarks) {
                            Label("分享书签", systemImage: "square.and.arrow.up")
                        }
                    }
                    
                    Button(action: {
                        viewModel.showImportFilePicker = true
                    }) {
                        Label("导入书签", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                
                Button(action: viewModel.addBookmark) {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel(Text("新增收藏"))
            }
        }
    }
}

#if os(macOS)
import AppKit

struct ShareSheet: NSViewRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented else { return }
        
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            if let window = nsView.window {
                let rect = CGRect(x: window.frame.midX, y: window.frame.midY, width: 0, height: 0)
                picker.show(relativeTo: rect, of: window.contentView ?? nsView, preferredEdge: .minY)
            } else {
                // Fallback: show from view itself
                picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
            }
            
            // Close the sheet after showing picker
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPresented = false
            }
        }
    }
}

extension UTType {
    static var json: UTType {
        if let type = UTType(filenameExtension: "json") {
            return type
        }
        return UTType.json
    }
}
#else
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            isPresented = false
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPicked: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: ([URL]) -> Void
        
        init(onPicked: @escaping ([URL]) -> Void) {
            self.onPicked = onPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPicked(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        }
    }
}
#endif
