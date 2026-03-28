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
        const patientDisplayName = computed(() => selectedPatient.value ? `${selectedPatient.value.firstName} ${selectedPatient.value.lastName}`.trim() : '');

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
                selectedStepIds.value = configuredSteps.map(step => step.id);
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
            });

            flatpickr('.date-picker-dob', {
                dateFormat: 'm/d/Y',
                allowInput: true
            });
            flatpickr('.date-picker.signature-date', {
                dateFormat: 'm/d/Y',
                allowInput: true
            });
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
                    payload.chartNumber = selectedPatient.value?.chartNumber || '';
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
            selectedStepIds.value = configuredSteps.map(step => step.id);
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
            selectedStepIds.value = configuredSteps.map(step => step.id);
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
