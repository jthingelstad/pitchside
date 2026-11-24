import PitchsideDesign
import PitchsideModel
import SwiftUI

/// The saved names, kept on this phone only: add, rename, forget.
struct RosterView: View {
  @Environment(AppModel.self) private var model
  @State private var newName = ""
  @State private var editing: SavedName?
  @State private var editText = ""
  @FocusState private var addFocused: Bool

  var body: some View {
    let totals = model.totals()
    Screen(title: "Roster") {
      Text("Saved names · kept on this phone only").psKick()
      Text("Names you type for a team are kept here for the next game. Nobody else sees them.").psHelp()
      if model.roster.isEmpty {
        Text("No names yet. Add one below, or type them when you set up a game.")
          .font(PSFont.body(16)).foregroundStyle(Color.psText)
      }
      VStack(spacing: 8) {
        ForEach(model.roster) { name in
          let t = totals[name.key]
          Button {
            editText = name.name
            editing = name
          } label: {
            HStack {
              Text(name.name).font(PSFont.body(17, .bold)).foregroundStyle(Color.psText)
              Spacer()
              Text(t.map { "\($0.games) \($0.games == 1 ? "game" : "games") · \(percent($0.hitPct))" } ?? "no games yet")
                .font(PSFont.body(14))
                .foregroundStyle(Color.psMuted)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .psBox()
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityHint("Rename or forget")
        }
      }
      Text("New name").font(PSFont.body(15, .bold)).foregroundStyle(Color.psText)
      HStack(spacing: 10) {
        TextField("First name", text: $newName)
          .font(PSFont.body(17))
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .submitLabel(.done)
          .focused($addFocused)
          .padding(.horizontal, 12)
          .frame(minHeight: 52)
          .background(Color.psField, in: RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 1))
          .onSubmit(add)
          .accessibilityLabel("New name")
        Button("Add", action: add)
          .buttonStyle(PSButtonStyle())
          .frame(width: 92)
          .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .navigationDestination(item: $editing) { name in
      NameEditor(text: $editText, back: { editing = nil }) {
        model.rename(name.key, to: editText)
        editing = nil
      } forget: {
        model.forget(name.key)
        editing = nil
      }
    }
  }

  func add() {
    model.save(name: newName)
    newName = ""
  }
}

struct NameEditor: View {
  @Binding var text: String
  let back: () -> Void
  let save: () -> Void
  let forget: () -> Void

  var body: some View {
    Screen(title: "Edit name", back: "Roster", onBack: back) {
      Text("Name").psKick()
      TextField("Name", text: $text)
        .font(PSFont.body(18, .bold))
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Color.psField, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 1))
        .accessibilityLabel("Name")
      Button("Save", action: save).buttonStyle(.psSolid)
        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
      Text("Games already played keep the name they were played with.").psHelp()
      Button("Forget this name", role: .destructive, action: forget).buttonStyle(.quiet)
    }
  }
}
