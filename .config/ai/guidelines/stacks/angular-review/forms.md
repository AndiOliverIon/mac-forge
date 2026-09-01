# Angular Review Guidelines — Forms (§8)

Topic file for Angular **review mode**. It is selected only by the mechanical routing rules in
`_core.md`, which is the sole authority for the selection corpus and trigger table. This file
intentionally contains no duplicate trigger list. When selected, read it in full; the broad baseline
in `_core.md` does not replace the detailed rules here.

---

## 8. Forms

**Use reactive forms exclusively.** Prefer typed forms for full type safety.

### Reactive Forms with Typed FormGroups

Angular's typed forms provide compile-time type checking for form structure and values.

**Form Control Syntax:** Always use `fb.control<Type>(defaultValue, options)` with the options object to specify validators and control behavior:

```typescript
// ✅ Options object syntax (recommended)
this.fb.control<string>('', {
    validators: [Validators.required],
    nonNullable: true,
    updateOn: 'blur', // Optional: 'change' (default), 'blur', or 'submit'
});

// ✅ Shorthand when you only need validators
this.fb.control<string>('', [Validators.required]);

// ❌ Avoid - untyped control
this.fb.control('');
```

```typescript
import { FormBuilder, FormGroup, FormControl, Validators } from '@angular/forms';

// ✅ Define form value interface
interface UserFormModel {
    firstName: string;
    lastName: string;
    email: string;
    age: number;
    acceptTerms: boolean;
}

// ✅ Define form controls interface
interface UserFormControls {
    firstName: FormControl<string>;
    lastName: FormControl<string>;
    email: FormControl<string>;
    age: FormControl<number>;
    acceptTerms: FormControl<boolean>;
}

@Component({
    selector: 'app-user-form',
    standalone: true,
    imports: [ReactiveFormsModule, KendoInputsModule],
    templateUrl: './user-form.component.html',
})
export class UserFormComponent {
    private readonly fb: FormBuilder = inject(FormBuilder);
    private readonly userService: UserService = inject(UserService);

    // ✅ Typed FormGroup using interface - compiler knows the structure
    protected userForm: FormGroup<UserFormControls> = this.fb.group({
        firstName: this.fb.control<string>('', {
            validators: [Validators.required, Validators.minLength(2)],
            nonNullable: true,
        }),
        lastName: this.fb.control<string>('', {
            validators: [Validators.required],
            nonNullable: true,
        }),
        email: this.fb.control<string>('', {
            validators: [Validators.required, Validators.email],
            nonNullable: true,
        }),
        age: this.fb.control<number>(0, {
            validators: [Validators.required, Validators.min(18)],
            nonNullable: true,
        }),
        acceptTerms: this.fb.control<boolean>(false, {
            validators: [Validators.requiredTrue],
            nonNullable: true,
        }),
    });

    public onSubmit(): void {
        if (this.userForm.valid) {
            // Form value is typed as UserFormModel
            const formValue: Partial<UserFormModel> = this.userForm.value;
            this.userService.createUser(formValue).subscribe({
                next: (user: User) => this.onCreateSuccess(user),
                error: (err: HttpErrorResponse) => this.notificationService.showError('Create failed', err),
            });
        }
    }

    // Access individual controls with type safety
    public get firstNameControl(): FormControl<string> {
        return this.userForm.controls.firstName;
    }
}
```

### NonNullableFormBuilder for Stricter Types

Use `NonNullableFormBuilder` to ensure **all** form values are never `null`. This is preferred over using `nonNullable: true` on individual controls.

**When to use:**

* ✅ `NonNullableFormBuilder` - When all controls in the form should be non-nullable (recommended)
* ✅ `FormBuilder` with `nonNullable: true` - When mixing nullable and non-nullable controls in the same form

```typescript
import { NonNullableFormBuilder } from '@angular/forms';

export class UserFormComponent {
    private readonly fb: NonNullableFormBuilder = inject(NonNullableFormBuilder);

    // All controls are automatically non-nullable with NonNullableFormBuilder
    protected userForm = this.fb.group({
        firstName: this.fb.control<string>('', {
            validators: [Validators.required],
        }), // Type: FormControl<string>
        age: this.fb.control<number>(0, {
            validators: [Validators.required],
        }), // Type: FormControl<number>
    });

    public onSubmit(): void {
        // getRawValue() returns non-nullable values
        const value: { firstName: string; age: number } = this.userForm.getRawValue();
        console.log(value.firstName); // always a string, never null
    }
}
```

### Form Arrays with Type Safety

```typescript
import { FormArray, FormControl } from '@angular/forms';

interface PhoneNumber {
    type: 'mobile' | 'home' | 'work';
    number: string;
}

interface PhoneNumberFormControls {
    type: FormControl<'mobile' | 'home' | 'work'>;
    number: FormControl<string>;
}

interface ContactFormControls {
    name: FormControl<string>;
    phoneNumbers: FormArray<FormGroup<PhoneNumberFormControls>>;
}

export class ContactFormComponent {
    private readonly fb: NonNullableFormBuilder = inject(NonNullableFormBuilder);

    protected contactForm: FormGroup<ContactFormControls> = this.fb.group({
        name: this.fb.control<string>('', {
            validators: [Validators.required],
        }),
        phoneNumbers: this.fb.array<FormGroup<PhoneNumberFormControls>>([]),
    });

    // Typed getter for FormArray
    public get phoneNumbers(): FormArray<FormGroup<PhoneNumberFormControls>> {
        return this.contactForm.controls.phoneNumbers;
    }

    public addPhoneNumber(): void {
        const phoneGroup: FormGroup<PhoneNumberFormControls> = this.fb.group({
            type: this.fb.control<'mobile' | 'home' | 'work'>('mobile', {
                validators: [Validators.required],
            }),
            number: this.fb.control<string>('', {
                validators: [Validators.required, Validators.pattern(/^\d{10}$/)],
            }),
        });
        this.phoneNumbers.push(phoneGroup);
    }

    public removePhoneNumber(index: number): void {
        this.phoneNumbers.removeAt(index);
    }
}
```

### Form Validation with Custom Validators

```typescript
import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

// ✅ Typed custom validator
export function passwordMatchValidator(): ValidatorFn {
    return (control: AbstractControl): ValidationErrors | null => {
        const password = control.get('password');
        const confirmPassword = control.get('confirmPassword');

        if (!password || !confirmPassword) {
            return null;
        }

        return password.value === confirmPassword.value ? null : { passwordMismatch: true };
    };
}

// Usage in component
export class RegistrationFormComponent {
    private readonly fb: NonNullableFormBuilder = inject(NonNullableFormBuilder);

    protected registrationForm = this.fb.group(
        {
            username: this.fb.control<string>('', {
                validators: [Validators.required],
            }),
            password: this.fb.control<string>('', {
                validators: [Validators.required, Validators.minLength(8)],
            }),
            confirmPassword: this.fb.control<string>('', {
                validators: [Validators.required],
            }),
        },
        { validators: [passwordMatchValidator()] }
    );
}
```

### Reactive Forms with Signals

Combine reactive forms with signals for enhanced reactivity:

```typescript
import { toSignal } from '@angular/core/rxjs-interop';

export class SearchFormComponent {
    private readonly fb: NonNullableFormBuilder = inject(NonNullableFormBuilder);
    private readonly searchService: SearchService = inject(SearchService);

    protected searchForm = this.fb.group({
        query: this.fb.control<string>(''),
        category: this.fb.control<string>('all'),
    });

    // Convert form value changes to signal
    protected formValue: Signal<{ query: string; category: string }> = toSignal(this.searchForm.valueChanges, {
        initialValue: this.searchForm.getRawValue(),
    });

    // Derived computed signal
    protected isSearchEnabled: Signal<boolean> = computed(() => {
        const value = this.formValue();
        return value.query.length >= 3;
    });

    // React to changes with effects
    constructor() {
        effect(() => {
            const value = this.formValue();
            console.log('Form changed:', value);
        });
    }
}
```

### Forms with Kendo UI Controls

Always use Kendo form controls with `formControlName`:

```html
<form
    [formGroup]="userForm"
    (ngSubmit)="onSubmit()"
>
    <!-- ✅ Kendo TextBox with formControlName -->
    <kendo-formfield>
        <kendo-label text="First Name"></kendo-label>
        <kendo-textbox
            formControlName="firstName"
            placeholder="Enter first name"
        ></kendo-textbox>
        <kendo-formerror>First name is required</kendo-formerror>
    </kendo-formfield>

    <!-- ✅ Kendo DatePicker -->
    <kendo-formfield>
        <kendo-label text="Birth Date"></kendo-label>
        <kendo-datepicker formControlName="birthDate"></kendo-datepicker>
    </kendo-formfield>

    <!-- ✅ Kendo DropDownList -->
    <kendo-formfield>
        <kendo-label text="Country"></kendo-label>
        <kendo-dropdownlist
            formControlName="country"
            [data]="countries()"
            textField="name"
            valueField="code"
        ></kendo-dropdownlist>
    </kendo-formfield>

    <button
        kendoButton
        themeColor="primary"
        type="submit"
        [disabled]="!userForm.valid"
    >
        Submit
    </button>
</form>
```

### Rules

* ✅ **Always use reactive forms** — never use template-driven forms.
* ✅ **Use typed FormGroups** with explicit control types for compile-time safety.
* ✅ **Use `fb.control<Type>(value, options)`** with options object for validators and control config.
* ✅ **Prefer `NonNullableFormBuilder`** to avoid null/undefined in form values.
* ✅ Use `nonNullable: true` in options when mixing nullable/non-nullable controls with `FormBuilder`.
* ✅ Use `FormArray` with proper typing for dynamic form fields.
* ✅ Define form interfaces/types for your form models.
* ✅ Use custom validators with proper typing (`ValidatorFn`, `AsyncValidatorFn`).
* ✅ Combine forms with signals using `toSignal(form.valueChanges)`.
* ✅ Use Kendo form controls with `formControlName` directive.
* ✅ Access form values with `getRawValue()` for non-nullable forms.
* ❌ Do not use template-driven forms (`ngModel`, `#templateVar`).
* ❌ Do not use untyped `FormGroup` — always specify control types.
* ❌ Avoid `form.value` with nullable forms — use `getRawValue()` instead.
* ❌ Avoid array shorthand `[validators]` — use options object `{ validators: [...] }` for clarity.

---
