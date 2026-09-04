using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace Notebar.App.Features;

/// <summary>The vertical rail on the panel's left edge: the pin toggle above the maximize
/// toggle, then Notes/Tasks/Settings, then the bottom-anchored collapse button (screen spec
/// §2/§3). See TabRail.xaml's own remarks for the two rules every element here follows: a
/// non-null Background on every clickable cell, and every colour a static {ThemeResource
/// ...} reference that this code-behind only ever shows or hides, never assigns.</summary>
internal sealed partial class TabRail : UserControl
{
    private PanelViewModel? _viewModel;
    private bool _isCompact;

    internal TabRail()
    {
        InitializeComponent();
    }

    /// <summary>Set once by RootPage right after construction. A plain settable property,
    /// not a DependencyProperty: nothing here needs XAML-side data binding -- every visual
    /// update is driven imperatively from PanelViewModel.PropertyChanged, matching how the
    /// rest of this codebase (PanelController, NoteEditorHost) wires state. The pin/maximize
    /// mutation itself still goes through PanelViewModel's own setters, never a Click
    /// handler here -- see PanelViewModel's remarks for why that distinction is what fixes
    /// the one-click-behind defect.</summary>
    internal PanelViewModel? ViewModel
    {
        get => _viewModel;
        set
        {
            if (_viewModel is not null) _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
            _viewModel = value;
            if (_viewModel is null) return;

            _viewModel.PropertyChanged += OnViewModelPropertyChanged;
            PinToggle.IsChecked = _viewModel.IsPinned;
            MaximizeToggle.IsChecked = _viewModel.IsMaximized;
            UpdatePinVisual();
            UpdateMaximizeVisual();
            UpdateSelectionVisuals();
        }
    }

    /// <summary>Screen spec §2 breakpoints: below the panel's default width the rail narrows
    /// to 44pt icon-only, labels dropped. RootPage computes isCompact from the window's
    /// actual width against Notebar.Core.Panel.PanelTiming.PanelWidth (never a duplicated
    /// literal) and calls this on every resize.</summary>
    internal void SetCompact(bool isCompact)
    {
        if (_isCompact == isCompact) return;
        _isCompact = isCompact;

        RailRoot.Width = isCompact ? 44 : 56;
        double itemHeight = isCompact ? 44 : 48;
        NotesButton.Height = itemHeight;
        TasksButton.Height = itemHeight;
        SettingsButton.Height = itemHeight;

        Visibility labelVisibility = isCompact ? Visibility.Collapsed : Visibility.Visible;
        NotesLabelOff.Visibility = labelVisibility;
        TasksLabelOff.Visibility = labelVisibility;
        SettingsLabelOff.Visibility = labelVisibility;
        // The "on" (selected/accent) labels only ever show at all when their tab is
        // selected -- UpdateSelectionVisuals already gates that -- so compact only needs to
        // additionally suppress them, never force them visible.
        if (isCompact)
        {
            NotesLabelOn.Visibility = Visibility.Collapsed;
            TasksLabelOn.Visibility = Visibility.Collapsed;
            SettingsLabelOn.Visibility = Visibility.Collapsed;
        }
        else
        {
            UpdateSelectionVisuals();
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(PanelViewModel.Selection):
                UpdateSelectionVisuals();
                break;
            case nameof(PanelViewModel.IsPinned):
                if (_viewModel is not null) PinToggle.IsChecked = _viewModel.IsPinned;
                UpdatePinVisual();
                break;
            case nameof(PanelViewModel.IsMaximized):
                if (_viewModel is not null) MaximizeToggle.IsChecked = _viewModel.IsMaximized;
                UpdateMaximizeVisual();
                break;
        }
    }

    private void OnNotesClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is not null) _viewModel.Selection = AppTab.Notes;
    }

    private void OnTasksClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is not null) _viewModel.Selection = AppTab.Tasks;
    }

    private void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is not null) _viewModel.Selection = AppTab.Settings;
    }

    private void OnCollapseClick(object sender, RoutedEventArgs e) => _viewModel?.RequestCollapse();

    /// <summary>Forwards the toggle's own already-committed IsChecked value into
    /// PanelViewModel.IsPinned's setter -- never "not the old value" computed here. See
    /// PanelViewModel's class remarks.</summary>
    private void OnPinToggled(object sender, RoutedEventArgs e)
    {
        if (_viewModel is not null) _viewModel.IsPinned = PinToggle.IsChecked ?? false;
        UpdatePinVisual();
    }

    private void OnMaximizeToggled(object sender, RoutedEventArgs e)
    {
        if (_viewModel is not null) _viewModel.IsMaximized = MaximizeToggle.IsChecked ?? false;
        UpdateMaximizeVisual();
    }

    private void UpdatePinVisual()
    {
        bool isPinned = _viewModel?.IsPinned ?? false;
        PinOnBg.Visibility = isPinned ? Visibility.Visible : Visibility.Collapsed;
        PinIconOff.Visibility = isPinned ? Visibility.Collapsed : Visibility.Visible;
        PinIconOn.Visibility = isPinned ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateMaximizeVisual()
    {
        bool isMaximized = _viewModel?.IsMaximized ?? false;
        MaximizeOnBg.Visibility = isMaximized ? Visibility.Visible : Visibility.Collapsed;
        MaximizeIconOff.Visibility = isMaximized ? Visibility.Collapsed : Visibility.Visible;
        MaximizeIconOn.Visibility = isMaximized ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateSelectionVisuals()
    {
        AppTab selection = _viewModel?.Selection ?? AppTab.Notes;
        SetSelected(AppTab.Notes, selection == AppTab.Notes);
        SetSelected(AppTab.Tasks, selection == AppTab.Tasks);
        SetSelected(AppTab.Settings, selection == AppTab.Settings);
    }

    private void SetSelected(AppTab tab, bool isSelected)
    {
        var v = isSelected ? Visibility.Visible : Visibility.Collapsed;
        var vOff = isSelected ? Visibility.Collapsed : Visibility.Visible;
        // The accent "on" label only ever shows when both selected AND not compact --
        // SetCompact already hides it outright while compact regardless of this call, so no
        // extra compact check is needed here.
        switch (tab)
        {
            case AppTab.Notes:
                NotesSelectedBg.Visibility = v;
                NotesIndicator.Visibility = v;
                NotesIconOff.Visibility = vOff;
                NotesIconOn.Visibility = v;
                if (!_isCompact) NotesLabelOn.Visibility = v;
                if (isSelected) NotesLabelOff.Visibility = Visibility.Collapsed;
                else if (!_isCompact) NotesLabelOff.Visibility = Visibility.Visible;
                break;
            case AppTab.Tasks:
                TasksSelectedBg.Visibility = v;
                TasksIndicator.Visibility = v;
                TasksIconOff.Visibility = vOff;
                TasksIconOn.Visibility = v;
                if (!_isCompact) TasksLabelOn.Visibility = v;
                if (isSelected) TasksLabelOff.Visibility = Visibility.Collapsed;
                else if (!_isCompact) TasksLabelOff.Visibility = Visibility.Visible;
                break;
            case AppTab.Settings:
                SettingsSelectedBg.Visibility = v;
                SettingsIndicator.Visibility = v;
                SettingsIconOff.Visibility = vOff;
                SettingsIconOn.Visibility = v;
                if (!_isCompact) SettingsLabelOn.Visibility = v;
                if (isSelected) SettingsLabelOff.Visibility = Visibility.Collapsed;
                else if (!_isCompact) SettingsLabelOff.Visibility = Visibility.Visible;
                break;
        }
    }

    // --- Hover (§3 "Hover (unselected): a radius.sm background at accent 4% opacity"; only
    // meaningful for an unselected tab -- the selected background already reads as "on". ---

    private void OnNotesPointerEntered(object sender, PointerRoutedEventArgs e) =>
        NotesHoverBg.Visibility = NotesSelectedBg.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    private void OnNotesPointerExited(object sender, PointerRoutedEventArgs e) => NotesHoverBg.Visibility = Visibility.Collapsed;

    private void OnTasksPointerEntered(object sender, PointerRoutedEventArgs e) =>
        TasksHoverBg.Visibility = TasksSelectedBg.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    private void OnTasksPointerExited(object sender, PointerRoutedEventArgs e) => TasksHoverBg.Visibility = Visibility.Collapsed;

    private void OnSettingsPointerEntered(object sender, PointerRoutedEventArgs e) =>
        SettingsHoverBg.Visibility = SettingsSelectedBg.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    private void OnSettingsPointerExited(object sender, PointerRoutedEventArgs e) => SettingsHoverBg.Visibility = Visibility.Collapsed;

    private void OnCollapsePointerEntered(object sender, PointerRoutedEventArgs e)
    {
        CollapseHoverBg.Visibility = Visibility.Visible;
        CollapseGlyphOff.Visibility = Visibility.Collapsed;
        CollapseGlyphOn.Visibility = Visibility.Visible;
    }

    private void OnCollapsePointerExited(object sender, PointerRoutedEventArgs e)
    {
        CollapseHoverBg.Visibility = Visibility.Collapsed;
        CollapseGlyphOff.Visibility = Visibility.Visible;
        CollapseGlyphOn.Visibility = Visibility.Collapsed;
    }
}
