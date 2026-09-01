# Angular Review Guidelines — UI Components — @ardis/ngx-kendo-ui (§12)

Topic file for Angular **review mode**. It is selected only by the mechanical routing rules in
`_core.md`, which is the sole authority for the selection corpus and trigger table. This file
intentionally contains no duplicate trigger list. When selected, read it in full; the broad baseline
in `_core.md` does not replace the detailed rules here.

---

## 12. UI Components — @ardis/ngx-kendo-ui

**Always prefer `@ardis/ngx-kendo-ui` components** over raw HTML elements or custom implementations when an equivalent component exists. This is a wrapper/extension library on top of Telerik Kendo UI for Angular.

### Priority Order for UI

1. `@ardis/ngx-kendo-ui` component
1. Native Kendo UI for Angular component (if not wrapped by Ardis)
1. Custom implementation (only when neither covers the use case)

**This priority order is enforced.** Using a raw HTML element, a plain Angular component, or a third-party widget when an `@ardis/ngx-kendo-ui` or Kendo equivalent exists is a violation. If you are unsure whether an equivalent exists, check the Ardis component library documentation before implementing.

> **Warning:** Do not use `<button>`, `<input>`, `<select>`, `<table>`, or similar raw HTML elements for UI interactions when a Kendo/Ardis equivalent is available. Replace with the appropriate Kendo component. Examples: `<button>` → `<button kendoButton>`, `<input>` → `<kendo-textbox>`, `<select>` → `<kendo-dropdownlist>`, `<table>` → `<ardis-grid>`.

### Import Pattern

```typescript
import { ArdisGridModule, ArdisButtonModule } from '@ardis/ngx-kendo-ui';
import { DialogService } from '@progress/kendo-angular-dialog';

@Component({
    standalone: true,
    imports: [ArdisGridModule, ArdisButtonModule],
})
export class MyComponent {
    // DialogService is injected, not imported in the component imports array
    private readonly dialogService: DialogService = inject(DialogService);
}
```

### Common Components — Usage Examples

**Grid / Data Table**

```html
<!-- ✅ Use Ardis/Kendo Grid, not custom tables -->
<ardis-grid
    [data]="invoices()"
    [pageSize]="20"
    [pageable]="true"
    [sortable]="true"
>
    <kendo-grid-column
        field="invoiceNumber"
        title="Invoice #"
    />
    <kendo-grid-column
        field="amount"
        title="Amount"
        format="{0:c}"
    />
    <kendo-grid-column
        field="status"
        title="Status"
    />
</ardis-grid>
```

**Forms & Inputs**

```html
<!-- ✅ Use Kendo form controls -->
<kendo-textbox
    [(ngModel)]="searchTerm"
    placeholder="Search..."
/>
<kendo-datepicker [(ngModel)]="dueDate" />
<kendo-dropdownlist
    [data]="statuses"
    [(ngModel)]="selectedStatus"
/>
```

**Dialogs**

**Always use Kendo `DialogService` with single component rendering.** Dialog components must extend `DialogContentBase` and include `kendo-dialog-titlebar` and `kendo-dialog-actions` in the template.

**Dialog Component Pattern:**

```typescript
import { Component, inject, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { DialogContentBase, DialogRef } from '@progress/kendo-angular-dialog';
import { ButtonsModule } from '@progress/kendo-angular-buttons';
import { InputsModule } from '@progress/kendo-angular-inputs';

interface InvoiceFormData {
    invoiceNumber: string;
    amount: number;
}

interface InvoiceDialogResult {
    action: 'save' | 'cancel';
    data?: InvoiceFormData;
}

@Component({
    selector: 'app-invoice-edit-dialog',
    standalone: true,
    imports: [ReactiveFormsModule, ButtonsModule, InputsModule],
    template: `
        <kendo-dialog-titlebar>
            {{ isEditMode ? 'Edit Invoice' : 'Create Invoice' }}
        </kendo-dialog-titlebar>

        <form
            [formGroup]="invoiceForm"
            class="dialog-content"
        >
            <kendo-formfield>
                <kendo-label text="Invoice Number"></kendo-label>
                <kendo-textbox
                    formControlName="invoiceNumber"
                    placeholder="INV-001"
                ></kendo-textbox>
            </kendo-formfield>

            <kendo-formfield>
                <kendo-label text="Amount"></kendo-label>
                <kendo-numerictextbox
                    formControlName="amount"
                    [min]="0"
                    [format]="'c2'"
                ></kendo-numerictextbox>
            </kendo-formfield>
        </form>

        <kendo-dialog-actions>
            <button
                kendoButton
                themeColor="base"
                (click)="onCancel()"
            >
                Cancel
            </button>
            <button
                kendoButton
                themeColor="primary"
                [disabled]="!invoiceForm.valid"
                (click)="onSave()"
            >
                {{ isEditMode ? 'Save' : 'Create' }}
            </button>
        </kendo-dialog-actions>
    `,
    styles: [
        `
            .dialog-content {
                padding: 24px;
                display: flex;
                flex-direction: column;
                gap: 16px;
            }
        `,
    ],
})
export class InvoiceEditDialogComponent extends DialogContentBase implements OnInit {
    private readonly fb: FormBuilder = inject(FormBuilder);

    // Input data from parent component
    public invoice: Invoice | null = null;
    public isEditMode: boolean = false;

    protected invoiceForm: FormGroup = this.fb.group({
        invoiceNumber: this.fb.control<string>('', {
            validators: [Validators.required],
        }),
        amount: this.fb.control<number>(0, {
            validators: [Validators.required, Validators.min(0.01)],
        }),
    });

    constructor(public dialog: DialogRef) {
        super(dialog);
    }

    public ngOnInit(): void {
        if (this.invoice) {
            this.isEditMode = true;
            this.invoiceForm.patchValue({
                invoiceNumber: this.invoice.invoiceNumber,
                amount: this.invoice.amount,
            });
        }
    }

    public onCancel(): void {
        const result: InvoiceDialogResult = { action: 'cancel' };
        this.dialog.close(result);
    }

    public onSave(): void {
        if (this.invoiceForm.valid) {
            const result: InvoiceDialogResult = {
                action: 'save',
                data: this.invoiceForm.getRawValue(),
            };
            this.dialog.close(result);
        }
    }
}
```

**Usage in Parent Component:**

```typescript
import { DialogService, DialogRef } from '@progress/kendo-angular-dialog';

export class InvoiceListComponent {
    private readonly dialogService: DialogService = inject(DialogService);
    private readonly invoiceService: InvoiceService = inject(InvoiceService);

    public openCreateDialog(): void {
        const dialogRef: DialogRef = this.dialogService.open({
            content: InvoiceEditDialogComponent,
            width: 500,
            height: 400,
        });

        dialogRef.result.subscribe({
            next: (result: InvoiceDialogResult) => {
                if (result?.action === 'save' && result.data) {
                    this.createInvoice(result.data);
                }
            },
            error: (err: unknown) => this.notificationService.showError('Dialog error', err),
        });
    }

    public openEditDialog(invoice: Invoice): void {
        const dialogRef: DialogRef = this.dialogService.open({
            content: InvoiceEditDialogComponent,
            width: 500,
            height: 400,
        });

        // Pass data to dialog component
        const dialogInstance = dialogRef.content.instance as InvoiceEditDialogComponent;
        dialogInstance.invoice = invoice;
        dialogInstance.isEditMode = true;

        dialogRef.result.subscribe({
            next: (result: InvoiceDialogResult) => {
                if (result?.action === 'save' && result.data) {
                    this.updateInvoice(invoice.id, result.data);
                }
            },
            error: (err: unknown) => this.notificationService.showError('Dialog error', err),
        });
    }

    private createInvoice(data: InvoiceFormData): void {
        this.invoiceService.create(data).subscribe({
            next: () => this.notificationService.showSuccess('Invoice created'),
            error: (err: HttpErrorResponse) => this.notificationService.showError('Create failed', err),
        });
    }

    private updateInvoice(id: string, data: InvoiceFormData): void {
        this.invoiceService.update(id, data).subscribe({
            next: () => this.notificationService.showSuccess('Invoice updated'),
            error: (err: HttpErrorResponse) => this.notificationService.showError('Update failed', err),
        });
    }
}
```

**Buttons**

```html
<!-- ✅ Always use Kendo Button, not <button> alone for UI actions -->
<button
    kendoButton
    themeColor="primary"
    (click)="save()"
>
    Save
</button>
<button
    kendoButton
    themeColor="base"
    (click)="cancel()"
>
    Cancel
</button>
```

### Rules

* ✅ Check `@ardis/ngx-kendo-ui` exports first before building any UI element.
* ✅ Use Kendo theming variables for colors — do not hardcode hex values.
* ✅ Use Kendo form controls inside reactive forms with `formControlName`.
* ✅ **Dialog components must extend `DialogContentBase`** from `@progress/kendo-angular-dialog`.
* ✅ **Include `<kendo-dialog-titlebar>` and `<kendo-dialog-actions>`** in dialog component templates.
* ✅ Pass `DialogRef` to the `super()` constructor in dialog components.
* ✅ Pass data to dialog components via instance properties after opening.
* ✅ Subscribe to `dialogRef.result` to handle dialog close/action results.
* ✅ Return typed result objects from dialog components (e.g., `{ action: 'save', data: {...} }`).
* ❌ Do not create custom data grids, date pickers, or dropdowns when Kendo equivalents exist.
* ❌ Do not add hover or motion effects to cards unless the requirement explicitly calls for them.
* ❌ Do not override Kendo component styles with `!important` — use the Kendo theming system.
* ❌ **Do not use declarative `<kendo-dialog>` with `*ngIf`** — always use `DialogService` instead.
* ❌ **Do not use string content or actions array** in `dialogService.open()` — always use a component.
* ❌ **Do not use raw HTML elements** (`<button>`, `<input>`, `<select>`, `<table>`) when a Kendo/Ardis equivalent exists.

---
