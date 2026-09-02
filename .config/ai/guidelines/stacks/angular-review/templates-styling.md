# Angular Review Guidelines — Templates and Styling (§16)

Topic file for Angular **review mode**. `_core.md` owns its routing triggers. Read this file in full
when selected; apply it together with the core rules.

## 16. Templates and Styling

### Rules

- Rendered components use separate files through `templateUrl` and, when custom styles exist,
  `styleUrl`. Omit `styleUrl` when no custom styles are needed and delete empty SCSS files.
- Only abstract, non-rendering base components may use `template: ''`.
- Never use non-empty inline component templates, `styles: [...]`, or template `style="..."`
  attributes.
- Use BEM for custom CSS classes. When SCSS contains a block with elements or modifiers, prefer
  nesting through `&__...` and `&--...`.
- Prefer Kendo CSS utility classes over custom CSS. Add custom styling only when the design system
  does not provide the required result.
- Use Kendo theme variables for colors, spacing, borders, shadows, typography, and other available
  design tokens. Do not hardcode an equivalent value.
- Use color only for semantic meaning, status, or necessary emphasis. Pair colored backgrounds with
  the corresponding `--kendo-color-on-*` variable.
- Keep custom styling minimal. Do not add custom grid or grid-row styling unless requested.
- Style `ardis-kendo-magic-grid` through its element selector directly, without a wrapper class.

### Component file shape

```typescript
@Component({
    selector: 'app-status-badge',
    standalone: true,
    templateUrl: './status-badge.component.html',
    styleUrl: './status-badge.component.scss',
})
export class StatusBadgeComponent {
    public status: InputSignal<'success' | 'error'> =
        input.required<'success' | 'error'>();
}
```

Use utilities directly when they cover the layout:

```html
<div class="k-display-flex k-align-items-center k-gap-2 k-p-3">
    <span class="k-text-bold">{{ label() }}</span>
</div>
```

For genuinely custom styling, combine BEM with Kendo tokens:

```scss
.status-badge {
    padding: var(--kendo-spacing-2) var(--kendo-spacing-4);
    border-radius: var(--kendo-border-radius-md);

    &--success {
        color: var(--kendo-color-on-success);
        background-color: var(--kendo-color-success);
    }

    &__icon {
        margin-inline-end: var(--kendo-spacing-2);
    }
}

ardis-kendo-magic-grid {
    width: 100%;
}
```
