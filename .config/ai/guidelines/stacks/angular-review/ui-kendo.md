# Angular Review Guidelines — UI Components and Kendo (§12)

Topic file for Angular **review mode**. `_core.md` owns its routing triggers. Read this file in full
when selected; apply it together with the core rules.

## 12. UI Components and Kendo

### Component priority

Use the first option that covers the requirement:

1. `@ardis/ngx-kendo-ui` component.
2. Native Kendo UI for Angular component when Ardis does not wrap it.
3. Custom implementation only when neither library covers the use case.

- Check the Ardis component-library exports before building a UI element.
- Do not create custom grids, date pickers, dropdowns, or other common controls when an Ardis/Kendo
  equivalent exists.
- Do not use raw interactive HTML when an equivalent exists: use `kendoButton`, Kendo inputs,
  Ardis/Kendo grids, and the matching component primitives.
- In the `@ardis/ngx-kendo-ui` library and projects that consume it, always wrap `ArdisDataProvider`,
  `ArdisConfigurationProvider`, and `ArdisExpressionConfigurationProvider` in `computed()`.
- Use Kendo icons before Font Awesome; use Font Awesome only when Kendo has no suitable icon.
- Use Kendo controls with `formControlName` in actual forms. Allow `ngModel` only for standalone
  controls and direct grid-cell or row editing outside a form.
- Use Kendo theme variables rather than hardcoded colors and do not override Kendo styles with
  `!important`.
- Do not add hover or motion effects to cards unless explicitly required.

```html
<form [formGroup]="filterForm">
    <kendo-textbox formControlName="searchTerm" />
</form>

<!-- Accepted only as standalone direct grid editing. -->
<kendo-numerictextbox
    [ngModel]="row.sequence"
    (ngModelChange)="updateSequence(row, $event)"
/>
```

### Dialog contract

- Open component content through `DialogService`; the component must extend `DialogContentBase`.
- Pass `DialogRef` through the constructor and call `super(dialog)`. This is the accepted exception
  to the general `inject()` preference because the base class requires it.
- Put `<kendo-dialog-titlebar>` and `<kendo-dialog-actions>` in the dialog template.
- Pass input data through the opened component instance.
- Subscribe to `dialogRef.result` with object syntax and meaningful error handling. Return a typed
  result object when the dialog has structured output.
- Close through an explicit component method rather than an inline `dialog.close(...)` expression.
- Do not use declarative `<kendo-dialog>` toggled by `*ngIf`, string `content`, or an `actions` array
  in `dialogService.open()`.
- Configure width and other dimensions in `DialogService.open()`, not in dialog SCSS. Dialog content
  may use `width: 100%` when needed.
- For grid dialogs, configure dimensions when opening, then let the grid fill the dialog body; do not
  add component-level `min-height` workarounds.
- Do not set `themeColor` on cancel actions. Reserve theme colors for affirmative or destructive
  actions.
- Aggregate cross-form or dialog-level errors into one shared `ardis-message-box`.
- Components extending `DialogContentBase` should use `...DialogComponent`, not
  `...PopupComponent`, unless a local convention requires otherwise.

### Canonical dialog component

```typescript
interface InvoiceFormData {
    reference: string;
}

interface InvoiceDialogResult {
    action: 'save' | 'cancel';
    data?: InvoiceFormData;
}

@Component({
    selector: 'app-invoice-dialog',
    standalone: true,
    imports: [ReactiveFormsModule, DialogModule, ButtonsModule, InputsModule],
    templateUrl: './invoice-dialog.component.html',
    styleUrl: './invoice-dialog.component.scss',
})
export class InvoiceDialogComponent extends DialogContentBase {
    private readonly fb: NonNullableFormBuilder = inject(NonNullableFormBuilder);

    public invoice: Invoice | null = null;

    protected invoiceForm = this.fb.group({
        reference: this.fb.control<string>('', {
            validators: [Validators.required],
        }),
    });

    public constructor(dialog: DialogRef) {
        super(dialog);
    }

    public cancel(): void {
        this.dialog.close({ action: 'cancel' } satisfies InvoiceDialogResult);
    }

    public save(): void {
        if (this.invoiceForm.invalid) {
            return;
        }

        this.dialog.close({
            action: 'save',
            data: this.invoiceForm.getRawValue(),
        } satisfies InvoiceDialogResult);
    }
}
```

```html
<kendo-dialog-titlebar>Invoice</kendo-dialog-titlebar>

<form [formGroup]="invoiceForm">
    <kendo-textbox formControlName="reference" />
</form>

<kendo-dialog-actions>
    <button
        kendoButton
        (click)="cancel()"
    >
        Cancel
    </button>
    <button
        kendoButton
        themeColor="primary"
        (click)="save()"
    >
        Save
    </button>
</kendo-dialog-actions>
```

### Opening, passing data, and receiving a result

```typescript
public edit(invoice: Invoice): void {
    const dialogRef: DialogRef = this.dialogService.open({
        content: InvoiceDialogComponent,
        width: 500,
        height: 400,
    });

    const instance: InvoiceDialogComponent =
        dialogRef.content.instance as InvoiceDialogComponent;
    instance.invoice = invoice;

    (dialogRef.result as Observable<unknown>).subscribe({
        next: (result: unknown) => {
            if (isInvoiceDialogResult(result) && result.action === 'save' && result.data) {
                this.update(invoice.id, result.data);
            }
        },
        error: (error: unknown) =>
            this.notificationService.showError('Dialog failed', error),
    });
}

function isInvoiceDialogResult(result: unknown): result is InvoiceDialogResult {
    return (
        typeof result === 'object' &&
        result !== null &&
        'action' in result &&
        (result.action === 'save' || result.action === 'cancel')
    );
}
```
