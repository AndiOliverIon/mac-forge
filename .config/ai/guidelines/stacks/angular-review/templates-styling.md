# Angular Review Guidelines — Templates & Styling (§16)

Topic file for Angular **review mode**. It is selected only by the mechanical routing rules in
`_core.md`, which is the sole authority for the selection corpus and trigger table. This file
intentionally contains no duplicate trigger list. When selected, read it in full; the broad baseline
in `_core.md` does not replace the detailed rules here.

---

## 16. Templates & Styling

**Templates and styles must always be in separate files.** Never use inline templates or inline styles.

### File Organization

```typescript
// ✅ Separate template and style files
@Component({
    selector: 'app-user-card',
    standalone: true,
    templateUrl: './user-card.component.html',
    styleUrl: './user-card.component.scss',
})
export class UserCardComponent {}

// ✅ If no styles are needed, omit styleUrl entirely
@Component({
    selector: 'app-simple-card',
    standalone: true,
    templateUrl: './simple-card.component.html',
})
export class SimpleCardComponent {}

// ❌ Never use inline template
@Component({
    selector: 'app-user-card',
    template: `<div>...</div>`,
})

// ❌ Never use inline styles
@Component({
    selector: 'app-user-card',
    styles: [`
        .container { padding: 20px; }
    `],
})
```

### SCSS and BEM Naming

**Use BEM (Block Element Modifier) naming convention** for all custom CSS classes.

```scss
// ✅ BEM naming convention
.user-card {
    // Block
    padding: 1rem;
    border-radius: 0.25rem;

    &__header {
        // Element
        display: flex;
        align-items: center;
    }

    &__title {
        // Element
        font-size: 1.25rem;
        font-weight: 600;
    }

    &__avatar {
        // Element
        width: 3rem;
        height: 3rem;
        border-radius: 50%;
    }

    &--featured {
        // Modifier
        border: 2px solid;
    }

    &--compact &__title {
        // Modifier affecting element
        font-size: 1rem;
    }
}

// ❌ Avoid non-BEM naming
.userCard {
}
.user_card_header {
}
.userCardTitle {
}
```

### Kendo UI CSS Utilities

**Prefer Kendo UI CSS utilities** over custom styles. Only write custom CSS when Kendo utilities don't cover your needs.

**Reference:** [Kendo Design System Utilities Documentation](https://www.telerik.com/design-system/docs/utils/get-started/introduction/)

```html
<!-- ✅ Use Kendo utility classes -->
<div class="k-display-flex k-gap-4 k-p-4 k-align-items-center">
    <span class="k-text-bold">Name:</span>
    <span>{{ user.name }}</span>
</div>

<div class="k-mb-4 k-p-3 k-rounded-md">Content with Kendo spacing and border radius</div>

<!-- ❌ Avoid custom CSS when Kendo utilities exist -->
<div style="display: flex; gap: 1rem; padding: 1rem;">...</div>
```

**Common Kendo UI Utility Classes:**

* **Layout**: `k-display-flex`, `k-display-grid`, `k-align-items-center`, `k-justify-content-between`
* **Spacing**: `k-p-4` (padding), `k-m-4` (margin), `k-gap-2` (gap), `k-mb-3` (margin-bottom)
* **Typography**: `k-text-bold`, `k-text-center`, `k-font-size-lg`
* **Borders**: `k-rounded-md`, `k-border`

### Kendo Theme Variables

**Use Kendo theme variables wherever possible** for colors, spacing, borders, shadows, and other design tokens. This ensures consistency with the design system and makes theming easier.

**Reference:** [Kendo Theme Variables Documentation](https://www.telerik.com/design-system/docs/themes/kendo-themes/default/theme-variables/)

```scss
// ✅ Use Kendo theme variables for colors, spacing, borders, etc.
.status-badge {
    &--success {
        background-color: var(--kendo-color-success);
        color: var(--kendo-color-on-success);
        border-radius: var(--kendo-border-radius-md);
        padding: var(--kendo-spacing-2) var(--kendo-spacing-4);
    }

    &--error {
        background-color: var(--kendo-color-error);
        color: var(--kendo-color-on-error);
        border-radius: var(--kendo-border-radius-md);
        padding: var(--kendo-spacing-2) var(--kendo-spacing-4);
    }

    &--warning {
        background-color: var(--kendo-color-warning);
        color: var(--kendo-color-on-warning);
        border-radius: var(--kendo-border-radius-md);
        padding: var(--kendo-spacing-2) var(--kendo-spacing-4);
    }
}

.custom-card {
    border: var(--kendo-border-width) solid var(--kendo-color-border);
    box-shadow: var(--kendo-elevation-1);
    font-family: var(--kendo-font-family);
    font-size: var(--kendo-font-size);
}

// ❌ Never hardcode values that exist in theme variables
.error-message {
    color: #ff0000; // ❌ Use var(--kendo-color-error)
    background: #fef2f2; // ❌ Use Kendo color variables
    padding: 8px 16px; // ❌ Use var(--kendo-spacing-2) var(--kendo-spacing-4)
    border-radius: 4px; // ❌ Use var(--kendo-border-radius-md)
}
```

**Common Kendo Theme Variable Categories:**

* **Colors**: `--kendo-color-primary`, `--kendo-color-success`, `--kendo-color-error`, `--kendo-color-warning`, `--kendo-color-info`, `--kendo-color-on-*` (text on colored backgrounds)
* **Spacing**: `--kendo-spacing-0` through `--kendo-spacing-24` (e.g., `--kendo-spacing-2`, `--kendo-spacing-4`)
* **Borders**: `--kendo-border-radius-sm`, `--kendo-border-radius-md`, `--kendo-border-radius-lg`, `--kendo-border-width`
* **Typography**: `--kendo-font-family`, `--kendo-font-size`, `--kendo-font-weight`, `--kendo-line-height`
* **Elevation/Shadows**: `--kendo-elevation-1` through `--kendo-elevation-9`
* **Layout**: `--kendo-spacing`, `--kendo-padding`

**Color Usage Guidelines:**

* **Only use color when it adds meaningful value** (status indication, emphasis, semantic meaning).
* Always use Kendo color palette variables — never hardcode hex values.
* For text on colored backgrounds, use the corresponding `--kendo-color-on-*` variable for proper contrast.

### Custom Components — Minimal Styling

When creating custom components, **keep custom styling to the absolute minimum.** Rely on Kendo components and utilities first.

```typescript
// ✅ Component using Kendo components and utilities
@Component({
    selector: 'app-status-badge',
    standalone: true,
    imports: [ButtonsModule],
    templateUrl: './status-badge.component.html',
    styleUrl: './status-badge.component.scss', // Only for truly custom styles
})
export class StatusBadgeComponent {
    public status: InputSignal<'active' | 'inactive'> = input.required<'active' | 'inactive'>();
}
```

```html
<!-- ✅ Template using Kendo utilities -->
<span
    class="k-badge k-rounded-md k-px-3 k-py-1"
    [class.k-badge-success]="status() === 'active'"
    [class.k-badge-error]="status() === 'inactive'"
>
    {{ status() }}
</span>
```

```scss
// status-badge.component.scss
// Only add custom styles that Kendo doesn't provide
.status-badge {
    &__icon {
        // Custom icon positioning not covered by Kendo utilities
        margin-right: var(--kendo-spacing-2);
        vertical-align: middle;
    }
}
```

### No Inline Styling

**Never use inline styles** in templates. All styling must be in separate SCSS files using Kendo theme variables or use Kendo utility classes.

```html
<!-- ✅ Use CSS classes with Kendo utilities -->
<div class="user-card__header k-display-flex k-gap-3">
    <img
        [src]="user().avatar"
        class="user-card__avatar"
    />
    <h3 class="user-card__title">{{ user().name }}</h3>
</div>

<!-- ❌ Never use inline styles -->
<div style="display: flex; gap: 12px;">
    <img
        [src]="user().avatar"
        style="width: 48px; height: 48px;"
    />
    <h3 style="font-size: 1.25rem;">{{ user().name }}</h3>
</div>
```

### Rules

* ✅ **Always use separate files** for templates (`templateUrl`) and styles (`styleUrl`).
* ✅ **Omit `styleUrl`** completely if no custom styles are needed.
* ✅ **Use BEM naming convention** for all custom CSS classes.
* ✅ **Prefer Kendo UI CSS utilities** over writing custom CSS.
* ✅ **Use Kendo theme variables** for colors, spacing, borders, shadows, typography, and other design tokens.
* ✅ **Only use color when it adds value** (status, emphasis, semantic meaning).
* ✅ **Keep custom styling minimal** in custom components.
* ✅ Delete empty SCSS files — don't leave unused files in the project.
* ❌ Never use inline templates (`template: ...`).
* ❌ Never use inline styles (`styles: [...]` or `style="..."`).
* ❌ Never hardcode values that exist as Kendo theme variables (colors, spacing, borders, etc.).
* ❌ Do not create custom CSS when Kendo utilities provide the same functionality.

---
