const { createApp, ref, computed, onMounted, watch, nextTick } = Vue;

createApp({
    setup() {
        const showAutofill = new URLSearchParams(location.search).has('test');
        const currentStep = ref(1);
        const isSubmitting = ref(false);
        const showSuccess = ref(false);
        const appStage = ref('landing');
        const currentMode = ref(null);
        const lookupLoading = ref(false);
        const lookupError = ref('');
        const lookupMatches = ref([]);
        const selectedPatient = ref(null);
        const selectedChartNumber = ref('');
        const selectedStepIds = ref([]);
        const hasEdited = ref(false);
        const suppressDirtyTracking = ref(false);
        const initialFormSnapshot = ref(SYGModels.buildInitialForm());
        const signatureDirty = ref({ cancellation: false, hipaa: false, signature: false });

        const configuredSteps = SYGModels.getConfiguredSteps();
        const availableSteps = configuredSteps;
        const steps = ref([...configuredSteps]);
        const totalSteps = computed(() => steps.value.length);
        const form = ref(SYGModels.buildInitialForm());
        const lookupForm = ref({ firstName: '', lastName: '', birthDate: '' });
        const allergies = SYGModels.allergies;
        const groupedConditions = SYGModels.groupedConditions;

        let signaturePadCancellation = null;
        let signaturePadHipaa = null;
        let signaturePadFinal = null;
        let autoNameSeed = '';

        const isReturningMode = computed(() => currentMode.value === 'returning');
        const currentStepTitle = computed(() => steps.value[currentStep.value - 1]?.title || '');
        const currentStepSubtitle = computed(() => steps.value[currentStep.value - 1]?.subtitle || '');
        const canSaveAndCheckIn = computed(() => isReturningMode.value && appStage.value === 'intake' && hasEdited.value && !isSubmitting.value);
        const successTitle = computed(() => isReturningMode.value ? 'Thank You' : "You're All Set!");
        const successMessage = computed(() => isReturningMode.value
            ? 'The doctor will see you soon. Please return the tablet to the front desk.'
            : "Welcome to Smile You're Golden. Please hand the iPad back to the front desk.");
        const successButtonLabel = computed(() => isReturningMode.value ? 'New Session' : 'New Patient Intake');
        const currentDate = computed(() => SYGModels.todayString());
        const patientDisplayName = computed(() => selectedPatient.value ? getPatientDisplayLabel(selectedPatient.value) : '');

        function toDisplayCase(value) {
            return (value || '')
                .trim()
                .split(/\s+/)
                .filter(Boolean)
                .map(part => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
                .join(' ');
        }

        function getPatientDisplayLabel(patient) {
            if (!patient) return '';
            const explicit = `${patient.firstName || ''} ${patient.lastName || ''}`.replace(/\s+/g, ' ').trim();
            if (explicit) return explicit;
            if (patient.displayName) return patient.displayName;
            const typed = `${lookupForm.value.firstName || ''} ${lookupForm.value.lastName || ''}`.replace(/\s+/g, ' ').trim();
            if (typed) return toDisplayCase(typed);
            if (patient.chartNumber) return `Patient ${patient.chartNumber}`;
            return 'Patient Match';
        }

        function patientFullName() {
            return `${form.value.firstName} ${form.value.middleInitial ? form.value.middleInitial + '. ' : ''}${form.value.lastName}`.replace(/\s+/g, ' ').trim();
        }

        function simpleFullName() {
            return `${form.value.firstName} ${form.value.lastName}`.replace(/\s+/g, ' ').trim();
        }

        function applyMasks() {
            const phoneMask = (value) => {
                if (!value) return '';
                const x = value.replace(/\D/g, '').match(/(\d{0,3})(\d{0,3})(\d{0,4})/);
                return !x[2] ? x[1] : '(' + x[1] + ') ' + x[2] + (x[3] ? '-' + x[3] : '');
            };

            const ssnMask = (value) => {
                if (!value) return '';
                const x = value.replace(/\D/g, '').match(/(\d{0,3})(\d{0,2})(\d{0,4})/);
                return !x[2] ? x[1] : x[1] + '-' + x[2] + (x[3] ? '-' + x[3] : '');
            };

            form.value.ssn = ssnMask(form.value.ssn);
            form.value.homePhone = phoneMask(form.value.homePhone);
            form.value.mobile = phoneMask(form.value.mobile);
            form.value.workPhone = phoneMask(form.value.workPhone);
            form.value.emergencyPhone = phoneMask(form.value.emergencyPhone);
        }

        function maskDateValue(value) {
            const digits = (value || '').replace(/\D/g, '').slice(0, 8);
            if (digits.length <= 2) return digits;
            if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`;
            return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`;
        }

        function parseStrictDate(value) {
            const masked = maskDateValue(value);
            const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(masked);
            if (!match) return undefined;

            const month = Number(match[1]);
            const day = Number(match[2]);
            const year = Number(match[3]);
            if (!month || !day || !year || month < 1 || month > 12 || day < 1 || day > 31) {
                return undefined;
            }

            const parsed = new Date(year, month - 1, day);
            if (
                parsed.getFullYear() !== year ||
                parsed.getMonth() !== month - 1 ||
                parsed.getDate() !== day
            ) {
                return undefined;
            }

            return parsed;
        }

        function formatDateValue(date) {
            if (!(date instanceof Date) || Number.isNaN(date.getTime())) return '';
            const month = `${date.getMonth() + 1}`.padStart(2, '0');
            const day = `${date.getDate()}`.padStart(2, '0');
            const year = `${date.getFullYear()}`;
            return `${month}/${day}/${year}`;
        }

        function attachDateInputMask(element) {
            if (!element || element.dataset.maskedDate === 'true') return;

            element.dataset.maskedDate = 'true';
            element.setAttribute('inputmode', 'numeric');
            element.setAttribute('maxlength', '10');
            element.setAttribute('placeholder', 'MM/DD/YYYY');

            const applyDateMask = () => {
                const start = element.selectionStart;
                const masked = maskDateValue(element.value);
                element.value = masked;
                if (typeof start === 'number') {
                    element.setSelectionRange(masked.length, masked.length);
                }
            };

            element.addEventListener('input', applyDateMask);
            element.addEventListener('blur', () => {
                const selectedDate = element._flatpickr?.selectedDates?.[0];
                const parsed = selectedDate || parseStrictDate(element.value);
                const nextValue = parsed ? formatDateValue(parsed) : maskDateValue(element.value);
                element.value = nextValue;
                syncDateModel(element, nextValue);
                if (element._flatpickr) {
                    if (parsed) {
                        element._flatpickr.setDate(parsed, false);
                    } else if (!element.value) {
                        element._flatpickr.clear();
                    }
                }
            });
        }

        function syncDerivedNames() {
            const fullName = simpleFullName();
            if (!fullName) {
                autoNameSeed = '';
                return;
            }

            if (!form.value.hipaaName || form.value.hipaaName === autoNameSeed) {
                form.value.hipaaName = fullName;
            }
            if (!form.value.signatureName || form.value.signatureName === autoNameSeed) {
                form.value.signatureName = fullName;
            }

            autoNameSeed = fullName;
        }

        async function withoutDirtyTracking(work) {
            suppressDirtyTracking.value = true;
            try {
                await work();
            } finally {
                setTimeout(() => {
                    suppressDirtyTracking.value = false;
                }, 0);
            }
        }

        function cloneFormState(source) {
            return JSON.parse(JSON.stringify(source));
        }

        function setByPath(target, path, value) {
            const segments = path.split('.');
            const lastSegment = segments.pop();
            let cursor = target;

            for (const segment of segments) {
                if (!cursor || typeof cursor !== 'object') {
                    return;
                }
                cursor = cursor[segment];
            }

            if (cursor && typeof cursor === 'object' && lastSegment) {
                cursor[lastSegment] = value;
            }
        }

        function syncDateModel(element, value) {
            const modelPath = element?.getAttribute('v-model');
            if (!modelPath) return;

            if (modelPath.startsWith('form.')) {
                setByPath(form.value, modelPath.slice(5), value);
                return;
            }

            if (modelPath.startsWith('lookupForm.')) {
                setByPath(lookupForm.value, modelPath.slice(11), value);
            }
        }

        function commitPickerDate(instance, date) {
            if (!instance || !(date instanceof Date) || Number.isNaN(date.getTime())) {
                return;
            }

            const formatted = formatDateValue(date);
            instance.setDate(date, false);
            instance.input.value = formatted;
            syncDateModel(instance.input, formatted);
            setTimeout(() => instance.close(), 0);
        }

        function bindSingleTapDateSelection(instance) {
            const container = instance?.calendarContainer;
            if (!container || container.dataset.singleTapBound === 'true') {
                return;
            }

            container.dataset.singleTapBound = 'true';
            container.addEventListener('pointerdown', (event) => {
                const day = event.target?.closest?.('.flatpickr-day');
                if (!day || day.classList.contains('disabled') || day.classList.contains('prevMonthDay') || day.classList.contains('nextMonthDay')) {
                    return;
                }

                if (!(day.dateObj instanceof Date) || Number.isNaN(day.dateObj.getTime())) {
                    return;
                }

                event.preventDefault();
                event.stopPropagation();
                commitPickerDate(instance, day.dateObj);
            }, true);
        }

        function getEditedStepIds() {
            if (!isReturningMode.value) {
                return steps.value.map(step => step.id);
            }

            const dirty = SYGModels.getDirtyStepIds(form.value, initialFormSnapshot.value, {
                signatures: signatureDirty.value
            });
            return steps.value
                .map(step => step.id)
                .filter(stepId => dirty.includes(stepId));
        }

        function refreshDirtyState() {
            if (!isReturningMode.value || appStage.value !== 'intake' || suppressDirtyTracking.value) {
                return;
            }
            hasEdited.value = getEditedStepIds().length > 0;
        }

        function resetPads() {
            signaturePadCancellation = null;
            signaturePadHipaa = null;
            signaturePadFinal = null;
        }

        async function resetSession() {
            await withoutDirtyTracking(async () => {
                form.value = SYGModels.buildInitialForm();
                lookupMatches.value = [];
                lookupError.value = '';
                selectedPatient.value = null;
                selectedChartNumber.value = '';
                selectedStepIds.value = [];
                currentStep.value = 1;
                steps.value = [...configuredSteps];
                hasEdited.value = false;
                initialFormSnapshot.value = cloneFormState(form.value);
                signatureDirty.value = { cancellation: false, hipaa: false, signature: false };
                autoNameSeed = '';
            });
            resetPads();
            await nextTick();
            initDatePickers();
        }

        function initDatePickers() {
            if (typeof flatpickr === 'undefined') return;

            document.querySelectorAll('.date-picker-dob, .date-picker.signature-date').forEach((element) => {
                if (element._flatpickr) {
                    element._flatpickr.destroy();
                }
                attachDateInputMask(element);
            });

            const pickerOptions = {
                dateFormat: 'm/d/Y',
                disableMobile: true,
                allowInput: true,
                parseDate: (datestr) => parseStrictDate(datestr),
                formatDate: (date) => formatDateValue(date),
                onReady: (_, __, instance) => {
                    bindSingleTapDateSelection(instance);
                },
                onChange: (selectedDates, dateStr, instance) => {
                    const selectedDate = selectedDates?.[0];
                    if (selectedDate) {
                        commitPickerDate(instance, selectedDate);
                        return;
                    }

                    const formatted = maskDateValue(dateStr);
                    instance.input.value = formatted;
                    syncDateModel(instance.input, formatted);
                },
                onValueUpdate: (_, dateStr, instance) => {
                    if (!dateStr) return;
                    const formatted = maskDateValue(dateStr);
                    instance.input.value = formatted;
                    syncDateModel(instance.input, formatted);
                }
            };

            flatpickr('.date-picker-dob', pickerOptions);
            flatpickr('.date-picker.signature-date', pickerOptions);
        }

        function resizeCanvas(canvas, pad) {
            if (!canvas || !pad || canvas.offsetWidth === 0) return;
            const ratio = Math.max(window.devicePixelRatio || 1, 1);
            const data = pad.toData();
            canvas.width = canvas.offsetWidth * ratio;
            canvas.height = canvas.offsetHeight * ratio;
            canvas.getContext('2d').scale(ratio, ratio);
            pad.clear();
            if (data.length) {
                pad.fromData(data);
            }
        }

        function initSignaturePad(type) {
            if (type === 'cancellation' && signaturePadCancellation) return;
            if (type === 'hipaa' && signaturePadHipaa) return;
            if (type === 'final' && signaturePadFinal) return;

            const canvasId = type === 'cancellation'
                ? 'signature-pad-cancellation'
                : type === 'hipaa'
                    ? 'signature-pad-hipaa'
                    : 'signature-pad';

            const canvas = document.getElementById(canvasId);
            if (!canvas) return;

            const pad = new SignaturePad(canvas, {
                backgroundColor: 'rgba(255, 255, 255, 0)',
                penColor: 'rgb(0, 0, 0)',
                onEnd: () => {
                    if (type === 'cancellation') signatureDirty.value.cancellation = true;
                    if (type === 'hipaa') signatureDirty.value.hipaa = true;
                    if (type === 'final') signatureDirty.value.signature = true;
                    refreshDirtyState();
                }
            });

            const onResize = () => resizeCanvas(canvas, pad);
            window.addEventListener('resize', onResize);
            onResize();

            if (type === 'cancellation') signaturePadCancellation = pad;
            if (type === 'hipaa') signaturePadHipaa = pad;
            if (type === 'final') signaturePadFinal = pad;
        }

        function initCurrentStepArtifacts() {
            const stepId = steps.value[currentStep.value - 1]?.id;
            if (stepId === 'cancellation') initSignaturePad('cancellation');
            if (stepId === 'hipaa') initSignaturePad('hipaa');
            if (stepId === 'signature') initSignaturePad('final');
        }

        function clearSignature(type) {
            if (type === 'cancellation' && signaturePadCancellation) {
                signaturePadCancellation.clear();
                signatureDirty.value.cancellation = false;
            }
            if (type === 'hipaa' && signaturePadHipaa) {
                signaturePadHipaa.clear();
                signatureDirty.value.hipaa = false;
            }
            if (type === 'final' && signaturePadFinal) {
                signaturePadFinal.clear();
                signatureDirty.value.signature = false;
            }
            refreshDirtyState();
        }

        function validateConsent() {
            const checkedSections = [];
            for (let i = 1; i <= 8; i++) {
                if (form.value.consent[`sec${i}`].checked) {
                    checkedSections.push(i);
                }
            }

            if (checkedSections.length === 0) {
                alert('Please check at least one consent section.');
                return false;
            }

            if (form.value.consent.sec1.checked) {
                const sec1 = form.value.consent.sec1;
                if (sec1.workDone.length === 0 && !sec1.other?.trim()) {
                    alert('Please select at least one item for Work To Be Done or enter an Other description.');
                    return false;
                }
            }

            if (form.value.consent.sec4.checked && !form.value.consent.sec4.teeth?.trim()) {
                alert('Please enter the teeth to be removed for section 4.');
                return false;
            }

            for (const i of checkedSections) {
                if (!form.value.consent[`sec${i}`].initials) {
                    alert(`Please provide your initials for Legal Section ${i}.`);
                    return false;
                }
            }

            return true;
        }

        function validateStep(stepId) {
            if (stepId === 'registration') {
                if (!form.value.firstName.trim() || !form.value.lastName.trim() || !form.value.birthDate.trim()) {
                    alert('Please complete the patient name and date of birth.');
                    return false;
                }
                if (!isReturningMode.value && !form.value.mobile.trim()) {
                    alert('Please provide the patient mobile number.');
                    return false;
                }
            }

            if (stepId === 'conditions' && !form.value.medical.healthAck) {
                alert('Please verify that the medical information is accurate.');
                return false;
            }

            if (stepId === 'consent' && !validateConsent()) {
                return false;
            }

            if (stepId === 'cancellation') {
                if (!form.value.cancellationAck) {
                    alert('Please check the cancellation policy acknowledgement.');
                    return false;
                }
                if (signaturePadCancellation && signaturePadCancellation.isEmpty()) {
                    alert('Please provide your signature for the Cancellation Policy.');
                    return false;
                }
            }

            if (stepId === 'hipaa') {
                const office = form.value.hipaaOfficeUse;
                const officeFilled = office.refused || office.communication || office.emergency || office.other;
                if (signaturePadHipaa && signaturePadHipaa.isEmpty() && !officeFilled) {
                    alert('Please provide your signature for the HIPAA privacy policy, or have the office staff fill out the exemption box.');
                    return false;
                }
            }

            if (stepId === 'signature' && signaturePadFinal && signaturePadFinal.isEmpty()) {
                alert('Please provide your final signature.');
                return false;
            }

            return true;
        }

        function validateCurrentStep() {
            const stepId = steps.value[currentStep.value - 1]?.id;
            return stepId ? validateStep(stepId) : true;
        }

        function validateSelectedFlow() {
            for (const step of steps.value) {
                if (!validateStep(step.id)) {
                    currentStep.value = steps.value.findIndex(candidate => candidate.id === step.id) + 1;
                    return false;
                }
            }
            return true;
        }

        function nextStep() {
            if (!validateCurrentStep()) return;
            if (currentStep.value < totalSteps.value) {
                currentStep.value++;
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        }

        function prevStep() {
            if (currentStep.value > 1) {
                currentStep.value--;
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        }

        function goToStep(stepNumber) {
            if (stepNumber < 1 || stepNumber > totalSteps.value) return;
            currentStep.value = stepNumber;
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        function syncClonedFormState(sourceSection, sectionClone) {
            const sourceControls = sourceSection.querySelectorAll('input, textarea, select');
            const cloneControls = sectionClone.querySelectorAll('input, textarea, select');
            const count = Math.min(sourceControls.length, cloneControls.length);

            for (let i = 0; i < count; i++) {
                const source = sourceControls[i];
                const clone = cloneControls[i];

                if (source instanceof HTMLInputElement && clone instanceof HTMLInputElement) {
                    clone.value = source.value;
                    clone.checked = source.checked;
                    if (source.type === 'checkbox' || source.type === 'radio') {
                        clone.toggleAttribute('checked', source.checked);
                    } else {
                        clone.setAttribute('value', source.value);
                    }
                    continue;
                }

                if (source instanceof HTMLTextAreaElement && clone instanceof HTMLTextAreaElement) {
                    clone.value = source.value;
                    clone.textContent = source.value;
                    continue;
                }

                if (source instanceof HTMLSelectElement && clone instanceof HTMLSelectElement) {
                    clone.value = source.value;
                    Array.from(clone.options).forEach(option => {
                        option.selected = option.value === source.value;
                    });
                }
            }
        }

        function buildPdfRenderNode(step) {
            const printableArea = document.getElementById('printable-area');
            const activeSection = Array.from(printableArea.querySelectorAll(`section[data-step-id="${step.id}"]`))
                .find(section => window.getComputedStyle(section).display !== 'none')
                || printableArea.querySelector(`section[data-step-id="${step.id}"]`);

            if (!activeSection) {
                throw new Error(`Unable to find section for ${step.title}.`);
            }

            const wrapper = document.createElement('div');
            wrapper.className = 'pdf-export-shell';

            const header = document.createElement('div');
            header.className = 'pdf-export-header';
            header.innerHTML = `
                <img src="logo.png" alt="Smile You're Golden Logo" class="practice-logo">
                <div class="practice-info">
                    <p><strong>Smile You're Golden Dental</strong></p>
                    <p>200 Chicago Ave, Oak Park, IL 60302</p>
                </div>
                <h1>${step.title}</h1>
                <p>${step.subtitle || ''}</p>
            `;

            const content = document.createElement('div');
            content.className = 'pdf-export-content';
            const sectionClone = activeSection.cloneNode(true);
            sectionClone.classList.remove('fade-in');
            sectionClone.style.display = 'block';
            sectionClone.hidden = false;
            sectionClone.querySelectorAll('.no-print').forEach(node => node.remove());
            syncClonedFormState(activeSection, sectionClone);
            sectionClone.querySelectorAll('canvas').forEach(canvas => {
                const image = document.createElement('img');
                try {
                    image.src = canvas.toDataURL('image/png');
                    image.className = 'pdf-signature-image';
                    image.alt = 'Signature';
                    image.style.width = '100%';
                    image.style.height = 'auto';
                    image.style.display = 'block';
                    image.style.background = '#fff';
                    image.style.border = '1px solid #ddd';
                    image.style.borderRadius = '12px';
                    canvas.replaceWith(image);
                } catch (error) {
                    console.warn('Unable to serialize signature canvas for PDF export.', error);
                }
            });
            content.appendChild(sectionClone);

            wrapper.appendChild(header);
            wrapper.appendChild(content);
            document.body.appendChild(wrapper);
            return wrapper;
        }

        async function renderPdfs(stepIds = null) {
            const element = document.getElementById('printable-area');
            const originalStep = currentStep.value;
            const pdfs = [];
            document.body.classList.add('generating-pdf');
            const renderSteps = stepIds && stepIds.length
                ? steps.value.filter(step => stepIds.includes(step.id))
                : steps.value;

            try {
                for (const step of renderSteps) {
                    const stepIndex = steps.value.findIndex(candidate => candidate.id === step.id);
                    if (stepIndex < 0) { continue; }
                    currentStep.value = stepIndex + 1;
                    await nextTick();
                    initCurrentStepArtifacts();
                    await new Promise(resolve => setTimeout(resolve, 400));

                    const base64 = await html2pdf().set({
                        margin: [0.3, 0.3],
                        filename: `Intake_${simpleFullName().replace(/\s+/g, '_') || 'Patient'}_${step.id}.pdf`,
                        image: { type: 'jpeg', quality: 0.98 },
                        html2canvas: { scale: 2, useCORS: true },
                        jsPDF: { unit: 'in', format: 'letter', orientation: 'portrait' }
                    }).from(element).outputPdf('datauristring');



                    let docType = 4;
                    if (['consent', 'cancellation', 'hipaa', 'signature'].includes(step.id)) {
                        docType = 3;
                    }

                    let title = `${step.title} Form`;
                    if (step.id === 'consent') title = 'Dental Consent Form';
                    if (step.id === 'hipaa') title = 'HIPAA Acknowledgment';

                    pdfs.push({ title, docType, base64 });
                }
            } finally {
                currentStep.value = originalStep;
                document.body.classList.remove('generating-pdf');
            }

            return pdfs;
        }

        async function submitFlow() {
            if (!validateSelectedFlow()) return;
            if (isReturningMode.value && !hasEdited.value) {
                alert('Make at least one edit before saving and checking in.');
                return;
            }

            isSubmitting.value = true;
            try {
                const editedStepIds = getEditedStepIds();
                const pdfs = await renderPdfs(isReturningMode.value ? editedStepIds : null);
                const payload = {
                    ...form.value,
                    flowType: currentMode.value,
                    selectedStepIds: steps.value.map(step => step.id),
                    editedStepIds,
                    pdfs
                };

                if (isReturningMode.value) {
                    let resolvedChartNumber = (selectedChartNumber.value || selectedPatient.value?.chartNumber || payload.chartNumber || '').trim();
                    if (!resolvedChartNumber && form.value.firstName?.trim() && form.value.lastName?.trim() && form.value.birthDate?.trim()) {
                        const matches = await SYGApi.searchPatients({
                            firstName: form.value.firstName,
                            lastName: form.value.lastName,
                            birthDate: form.value.birthDate
                        });
                        if (Array.isArray(matches) && matches.length === 1 && matches[0]?.chartNumber) {
                            resolvedChartNumber = `${matches[0].chartNumber}`.trim();
                            selectedChartNumber.value = resolvedChartNumber;
                            selectedPatient.value = matches[0];
                        }
                    }
                    payload.chartNumber = resolvedChartNumber;
                    await SYGApi.saveCheckIn(payload);
                } else {
                    await SYGApi.createIntake(payload);
                }

                showSuccess.value = true;
                hasEdited.value = false;
                initialFormSnapshot.value = cloneFormState(form.value);
                signatureDirty.value = { cancellation: false, hipaa: false, signature: false };
            } catch (err) {
                alert(`Submission error: ${err.message}`);
            } finally {
                isSubmitting.value = false;
            }
        }

        async function startNewPatient() {
            currentMode.value = 'new';
            appStage.value = 'intake';
            showSuccess.value = false;
            await resetSession();
            await nextTick();
            initCurrentStepArtifacts();
        }

        async function startReturningPatient() {
            currentMode.value = 'returning';
            appStage.value = 'lookup';
            showSuccess.value = false;
            lookupForm.value = { firstName: '', lastName: '', birthDate: '' };
            await resetSession();
            await nextTick();
            initDatePickers();
        }

        async function searchReturningPatients() {
            lookupError.value = '';
            lookupMatches.value = [];

            if (!lookupForm.value.firstName.trim() || !lookupForm.value.lastName.trim() || !lookupForm.value.birthDate.trim()) {
                lookupError.value = 'Enter first name, last name, and birthdate to continue.';
                return;
            }

            lookupLoading.value = true;
            try {
                lookupMatches.value = await SYGApi.searchPatients(lookupForm.value);
                if (lookupMatches.value.length === 0) {
                    lookupError.value = 'No matching patient was found. Please ask the front desk for help.';
                }
            } catch (err) {
                lookupError.value = err.message;
            } finally {
                lookupLoading.value = false;
            }
        }

        async function chooseReturningPatient(match) {
            selectedPatient.value = match;
            selectedChartNumber.value = `${match?.chartNumber || ''}`.trim();
            selectedStepIds.value = [];
            await withoutDirtyTracking(async () => {
                form.value = SYGModels.applyPatientToForm(match);
                autoNameSeed = simpleFullName();
                initialFormSnapshot.value = cloneFormState(form.value);
                signatureDirty.value = { cancellation: false, hipaa: false, signature: false };
                hasEdited.value = false;
            });
            appStage.value = 'returningSelect';
            await nextTick();
            initDatePickers();
        }

        async function beginReturningCheckIn() {
            if (selectedStepIds.value.length === 0) {
                alert('Select at least one form before starting check-in.');
                return;
            }
            steps.value = configuredSteps.filter(step => selectedStepIds.value.includes(step.id));
            currentStep.value = 1;
            hasEdited.value = false;
            initialFormSnapshot.value = cloneFormState(form.value);
            signatureDirty.value = { cancellation: false, hipaa: false, signature: false };
            appStage.value = 'intake';
            await nextTick();
            initDatePickers();
            initCurrentStepArtifacts();
        }

        function resetForm() {
            location.href = '/';
        }

        function autofillTestData() {
            const seed = Math.floor(Math.random() * 10000);
            form.value.firstName = `Test${seed}`;
            form.value.lastName = 'Automated';
            form.value.middleInitial = 'X';
            form.value.birthDate = '01/15/1985';
            form.value.gender = 'M';
            form.value.mobile = '(555) 987-6543';
            form.value.homePhone = '(555) 123-4567';
            form.value.email = `test${seed}@example.com`;
            form.value.street = '123 Fake Street';
            form.value.city = 'Chicago';
            form.value.state = 'IL';
            form.value.zip = '60601';
            form.value.emergencyContact = 'Jane Doe';
            form.value.emergencyPhone = '(555) 111-2222';
            form.value.relationship = 'Self';
            form.value.cancellationAck = true;
            form.value.medical.healthAck = true;
            form.value.consent.sec1.checked = true;
            form.value.consent.sec1.workDone = ['Fillings'];
            for (let i = 1; i <= 8; i++) {
                form.value.consent[`sec${i}`].initials = 'TA';
            }
            syncDerivedNames();
        }

        watch(form, () => {
            applyMasks();
            syncDerivedNames();
            refreshDirtyState();
        }, { deep: true });

        watch([appStage, currentStep], async () => {
            await nextTick();
            initDatePickers();
            if (appStage.value === 'intake') {
                initCurrentStepArtifacts();
            }
        });

        onMounted(async () => {
            selectedStepIds.value = [];
            await nextTick();
            initDatePickers();
        });

        return {
            currentStep,
            totalSteps,
            steps,
            form,
            currentDate,
            allergies,
            groupedConditions,
            currentStepTitle,
            currentStepSubtitle,
            isSubmitting,
            showSuccess,
            appStage,
            currentMode,
            isReturningMode,
            lookupForm,
            lookupLoading,
            lookupError,
            lookupMatches,
            selectedPatient,
            selectedStepIds,
            availableSteps,
            hasEdited,
            canSaveAndCheckIn,
            successTitle,
            successMessage,
            successButtonLabel,
            patientDisplayName,
            getPatientDisplayLabel,
            showAutofill,
            nextStep,
            prevStep,
            goToStep,
            clearSignature,
            submitForm: submitFlow,
            resetForm,
            autofillTestData,
            startNewPatient,
            startReturningPatient,
            searchReturningPatients,
            chooseReturningPatient,
            beginReturningCheckIn,
            patientFullName
        };
    }
}).mount('#app');
