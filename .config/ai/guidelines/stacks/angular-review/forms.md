# Angular Review Guidelines — Forms (§8)

Topic file for Angular **review mode**. `_core.md` owns its routing triggers. Read this file in full
when selected; apply it together with the core rules.

## 8. Forms

### Rules

- Use reactive forms for actual forms, validation flows, and multi-field dialogs.
- Allow `ngModel` only for standalone controls and direct grid-cell or row editing outside a form.
  Never mix it with reactive-form state inside an actual form.
- Prefer typed `FormGroup`, `FormControl`, and `FormArray`, but accept bare or inferred form types
  when they match the surrounding feature.
- Define form model/control interfaces or types when they clarify a non-trivial form.
- Prefer `NonNullableFormBuilder` when all controls should be non-nullable. When mixing nullable and
  non-nullable controls with `FormBuilder`, set `nonNullable: true` on the applicable controls.
- Configure controls with `fb.control<Type>(value, { validators: [...] })`. Do not use the validator
  array shorthand.
- Type custom validators as `ValidatorFn` or `AsyncValidatorFn`.
- Use Kendo form controls with `formControlName`.
- Use `getRawValue()` for non-nullable forms. Avoid `form.value` when nullable values would leak into
  the result.
- Convert `form.valueChanges` with `toSignal()` when form state must participate in signal-based
  derivation.

### Canonical typed form

This example fixes the expected control configuration, typed-array, Kendo binding, and value-access
shape without requiring every accepted local form to declare an explicit `FormGroup` type.

```typescript
interface ContactControls {
    name: FormControl<string>;
    phoneNumbers: FormArray<FormControl<string>>;
}

interface ContactFormValue {
    name: string;
    phoneNumbers: string[];
}

export class ContactFormComponent {
    private readonly fb: NonNullableFormBuilder = inject(NonNullableFormBuilder);

    protected contactForm: FormGroup<ContactControls> = this.fb.group({
        name: this.fb.control<string>('', {
            validators: [Validators.required],
        }),
        phoneNumbers: this.fb.array<FormControl<string>>([]),
    });

    protected formValue: Signal<Partial<ContactFormValue>> = toSignal(
        this.contactForm.valueChanges,
        { initialValue: this.contactForm.getRawValue() }
    );

    public addPhoneNumber(): void {
        this.contactForm.controls.phoneNumbers.push(
            this.fb.control<string>('', {
                validators: [Validators.required],
            })
        );
    }

    public submit(): void {
        if (this.contactForm.invalid) {
            return;
        }

        const value: ContactFormValue = this.contactForm.getRawValue();
        this.save(value);
    }
}
```

```html
<form
    [formGroup]="contactForm"
    (ngSubmit)="submit()"
>
    <kendo-formfield>
        <kendo-label text="Name" />
        <kendo-textbox formControlName="name" />
        <kendo-formerror>Name is required</kendo-formerror>
    </kendo-formfield>

    <button
        kendoButton
        themeColor="primary"
        type="submit"
        [disabled]="contactForm.invalid"
    >
        Save
    </button>
</form>
```

### Custom validator shape

```typescript
export function passwordMatchValidator(): ValidatorFn {
    return (control: AbstractControl): ValidationErrors | null => {
        const password: unknown = control.get('password')?.value;
        const confirmation: unknown = control.get('confirmation')?.value;

        return password === confirmation ? null : { passwordMismatch: true };
    };
}
```

### Standalone editing exception

This is accepted only when the control is not part of a form, such as direct grid-cell editing:

```html
<kendo-numerictextbox
    [ngModel]="row.sequence"
    (ngModelChange)="updateSequence(row, $event)"
/>
```
