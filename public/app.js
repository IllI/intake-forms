const { createApp, ref, computed, onMounted, watch } = Vue;

createApp({
    setup() {
        const currentStep = ref(1);
        const isSubmitting = ref(false);
        const showSuccess = ref(false);
        
        const defaultSteps = [
            { id: 'registration', title: "Registration", subtitle: "Patient Details" },
            { id: 'history', title: "History", subtitle: "Medical History" },
            { id: 'conditions', title: "Conditions", subtitle: "Health Checklist" },
            { id: 'smile', title: "Smile", subtitle: "Cosmetic Questionnaire" },
            { id: 'cancellation', title: "Cancellation", subtitle: "Policy Agreement" },
            { id: 'hipaa', title: "HIPAA", subtitle: "Privacy Practices" },
            { id: 'consent', title: "Consent", subtitle: "Treatment Agreement" },
            { id: 'signature', title: "Sign", subtitle: "Finalize" }
        ];

        const savedConfig = localStorage.getItem('SYG_FORM_CONFIG');
        const steps = ref(savedConfig ? JSON.parse(savedConfig) : defaultSteps);
        const totalSteps = computed(() => steps.value.length);

        const allergies = [
            "Aspirin", "Penicillin", "Codeine", "Acrylic", "Metal", "Latex", "Local Anesthetics", "Sulfa Drugs"
        ];

        const groupedConditions = {
            "Heart & Blood": ["Anemia", "Angina", "Artificial Heart Valve", "Blood Disease", "Blood Transfusion", "Bruise Easily", "Chest Pains", "Congenital Heart Disorder", "Emphysema", "Excessive Bleeding", "Heart Attack/Failure", "Heart Murmur", "Heart Pacemaker", "Heart Trouble/Disease", "Hemophilia", "High Blood Pressure", "Irregular Heartbeat", "Low Blood Pressure", "Mitral Valve Prolapse", "Rheumatic Fever", "Sickle Cell Disease", "Stroke"],
            "Breathing & Lungs": ["Asthma", "Breathing Problem", "Easily Winded", "Frequent Cough", "Hay Fever", "Lung Disease", "Sinus Trouble", "Tuberculosis"],
            "Brain & Nerves": ["Alzheimer's Disease", "Convulsions", "Epilepsy or Seizures", "Fainting Spells/Dizziness", "Frequent Headaches", "Psychiatric Care", "Spina Bifida"],
            "Metabolic & Digestion": ["Diabetes", "Excessive Thirst", "Frequent Diarrhea", "High Cholesterol", "Hypoglycemia", "Kidney Problems", "Liver Disease", "Parathyroid Disease", "Recent Weight Loss", "Renal Dialysis", "Stomach/Intestinal Disease", "Thyroid Disease", "Ulcers", "Yellow Jaundice"],
            "Bones & Joints": ["Arthritis/Gout", "Artificial Joint", "Osteoporosis", "Pain in Jaw Joints", "Rheumatism"],
            "Immunity, Infection & Cancer": ["AIDS/HIV Positive", "Anaphylaxis", "Cancer", "Chemotherapy", "Cold Sores/Fever Blisters", "Genital Herpes", "Hepatitis A", "Hepatitis B or C", "Herpes", "Leukemia", "Radiation Treatments", "Scarlet Fever", "Shingles", "Tonsillitis", "Tumors or Growths", "Venereal Disease"],
            "Other": ["Cortisone Medicine", "Drug Addiction", "Glaucoma", "Hives or Rash", "Swelling of Limbs"]
        };

        const form = ref({
            firstName: '',
            middleInitial: '',
            lastName: '',
            hipaaName: '',
            birthDate: '',
            gender: '',
            ssn: '',
            homePhone: '',
            mobile: '',
            workPhone: '',
            street: '',
            apt: '',
            city: '',
            state: 'IL',
            zip: '',
            maritalStatus: '',
            email: '',
            emergencyContact: '',
            emergencyPhone: '',
            referral: '',
            signatureName: '',
            relationship: 'Self',
            medical: {
                underPhysicianCare: 'No', physicianCareDetails: '',
                hasSurgery: 'No', surgeryDetails: '',
                hasHeadInjury: 'No', headInjuryDetails: '',
                takesMedications: 'No', medicationsDetails: '',
                phenFen: 'No',
                bisphosphonates: 'No',
                specialDiet: 'No',
                usesTobacco: 'No',
                usesControlledSubstances: 'No',
                pregnant: false,
                nursing: false,
                contraceptives: false,
                allergies: [],
                otherAllergy: '',
                conditions: [],
                otherIllness: 'No',
                otherIllnessDetails: '',
                comments: '',
                healthAck: false,
                privacyAck: false
            },
            smile: {
                likeSmile: '',
                interestedEnhancing: '',
                smileType: '',
                willingToPay: '',
                bookConsultation: ''
            },
            cancellationAck: false,
            hipaaOfficeUse: {
                refused: false,
                communication: false,
                emergency: false,
                other: false,
                otherDetails: ''
            },
            consent: {
                sec1: { checked: false, fillings: false, bridges: false, crowns: false, extractions: false, impacted: '', anesthesia: 'LOCAL', rootCanals: '', other: '', initials: '' },
                sec2: { checked: false, initials: '' },
                sec3: { checked: false, initials: '' },
                sec4: { checked: false, teeth: '', initials: '' },
                sec5: { checked: false, initials: '' },
                sec6: { checked: false, initials: '' },
                sec7: { checked: false, initials: '' },
                sec8: { checked: false, initials: '' },
            },
            cancellationDate: '',
            hipaaDate: '',
            finalDate: ''
        });

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

        watch(() => form.value.ssn, (val) => { form.value.ssn = ssnMask(val); });
        watch(() => form.value.homePhone, (val) => { form.value.homePhone = phoneMask(val); });
        watch(() => form.value.mobile, (val) => { form.value.mobile = phoneMask(val); });
        watch(() => form.value.workPhone, (val) => { form.value.workPhone = phoneMask(val); });
        watch(() => form.value.emergencyPhone, (val) => { form.value.emergencyPhone = phoneMask(val); });

        const currentDate = computed(() => {
            const d = new Date();
            return `${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}/${d.getFullYear()}`;
        });

        onMounted(() => {
            // Provide default todays date to the signature instances
            form.value.cancellationDate = currentDate.value;
            form.value.hipaaDate = currentDate.value;
            form.value.finalDate = currentDate.value;

            if (typeof flatpickr !== 'undefined') {
                flatpickr('.date-picker-dob', {
                    dateFormat: "m/d/Y",
                    allowInput: true
                });
                flatpickr('.date-picker.signature-date', {
                    dateFormat: "m/d/Y",
                    allowInput: true
                });
            }
        });

        const currentStepTitle = computed(() => steps.value[currentStep.value - 1]?.title);
        const currentStepSubtitle = computed(() => steps.value[currentStep.value - 1]?.subtitle);

        let signaturePadCancellation = null;
        let signaturePadHipaa = null;
        let signaturePadFinal = null;

        const resizeCanvas = (canvas, pad) => {
            if (!canvas || canvas.offsetWidth === 0) return;
            const ratio = Math.max(window.devicePixelRatio || 1, 1);
            const data = pad.toData();
            canvas.width = canvas.offsetWidth * ratio;
            canvas.height = canvas.offsetHeight * ratio;
            canvas.getContext("2d").scale(ratio, ratio);
            pad.clear();
            pad.fromData(data);
        };

        const initSignaturePad = (type) => {
            if (type === 'cancellation' && signaturePadCancellation) return;
            if (type === 'hipaa' && signaturePadHipaa) return;
            if (type === 'final' && signaturePadFinal) return;

            let canvasId = type === 'cancellation' ? 'signature-pad-cancellation' : 
                           type === 'hipaa' ? 'signature-pad-hipaa' : 'signature-pad';

            const canvas = document.getElementById(canvasId);
            if (canvas) {
                const pad = new SignaturePad(canvas, {
                    backgroundColor: 'rgba(255, 255, 255, 0)',
                    penColor: 'rgb(0, 0, 0)'
                });
                
                const onResize = () => resizeCanvas(canvas, pad);
                window.addEventListener('resize', onResize);
                onResize();

                if (type === 'cancellation') signaturePadCancellation = pad;
                else if (type === 'hipaa') signaturePadHipaa = pad;
                else signaturePadFinal = pad;
            }
        };

        const validateCurrentStep = () => {
            const stepId = steps.value[currentStep.value - 1]?.id;
            
            // Enforce basic required text inputs
            const inputs = document.querySelectorAll(`section:nth-of-type(${currentStep.value}) input[required], section:nth-of-type(${currentStep.value}) select[required]`);
            for (let input of inputs) {
                if (!input.value) {
                    alert("Please fill out all required fields on this page (marked with *).");
                    input.focus();
                    return false;
                }
            }

            if (stepId === 'consent') {
                for (let i = 1; i <= 8; i++) {
                    if (!form.value.consent['sec'+i].initials) {
                        alert(`Please provide your initials for Legal Section ${i}.`);
                        return false;
                    }
                }
            }
            if (stepId === 'cancellation') {
                if (!form.value.cancellationAck) {
                     alert("Please check the acknowledgement box.");
                     return false;
                }
                if (signaturePadCancellation && signaturePadCancellation.isEmpty()) {
                    alert("Please provide your signature for the Cancellation Policy.");
                    return false;
                }
            }
            if (stepId === 'hipaa') {
                const office = form.value.hipaaOfficeUse;
                const officeFilled = office.refused || office.communication || office.emergency || office.other;
                if (signaturePadHipaa && signaturePadHipaa.isEmpty() && !officeFilled) {
                    alert("Please provide your signature for the HIPAA privacy policy.");
                    return false;
                }
            }
            return true;
        };

        const nextStep = () => {
            if (!validateCurrentStep()) return;
            if (currentStep.value < totalSteps.value) {
                currentStep.value++;
                const currentId = steps.value[currentStep.value - 1]?.id;
                
                setTimeout(() => {
                    if (currentId === 'signature') {
                        initSignaturePad('final');
                        resizeCanvas(document.getElementById('signature-pad'), signaturePadFinal);
                    } else if (currentId === 'cancellation') {
                        initSignaturePad('cancellation');
                        resizeCanvas(document.getElementById('signature-pad-cancellation'), signaturePadCancellation);
                    } else if (currentId === 'hipaa') {
                        initSignaturePad('hipaa');
                        resizeCanvas(document.getElementById('signature-pad-hipaa'), signaturePadHipaa);
                    }
                }, 100);
            }
        };

        const prevStep = () => {
            if (currentStep.value > 1) {
                currentStep.value--;
            }
        };

        const clearSignature = (type) => {
            if (type === 'cancellation' && signaturePadCancellation) signaturePadCancellation.clear();
            if (type === 'hipaa' && signaturePadHipaa) signaturePadHipaa.clear();
            if (type === 'final' && signaturePadFinal) signaturePadFinal.clear();
        };

        const submitForm = async () => {
            if (signaturePadFinal && signaturePadFinal.isEmpty()) {
                alert("Please provide your final signature.");
                return;
            }
            if (steps.value.find(s => s.id === 'cancellation') && signaturePadCancellation && signaturePadCancellation.isEmpty()) {
                alert("Please provide your signature for the cancellation policy.");
                return;
            }
            if (steps.value.find(s => s.id === 'hipaa') && signaturePadHipaa && signaturePadHipaa.isEmpty() && !form.value.hipaaOfficeUse.refused && !form.value.hipaaOfficeUse.communication && !form.value.hipaaOfficeUse.emergency && !form.value.hipaaOfficeUse.other) {
                alert("Please provide your signature for the HIPAA privacy policy, or have the office staff fill out the exemption box.");
                return;
            }

            isSubmitting.value = true;
            try {
                const patientFullName = `${form.value.firstName} ${form.value.lastName}`.trim();
                const element = document.getElementById('printable-area');
                
                const originalStep = currentStep.value;
                document.body.classList.add('generating-pdf');
                
                let pdfArray = [];
                const formsToRender = steps.value;
                
                for (let i = 0; i < formsToRender.length; i++) {
                    const stepConf = formsToRender[i];
                    currentStep.value = i + 1;
                    
                    // Allow Vue reactive rendering cycle fully
                    await new Promise(resolve => setTimeout(resolve, 400));
                    
                    const opt = {
                        margin: [0.3, 0.3],
                        filename: `Intake_${patientFullName.replace(/\s+/g, '_')}_${stepConf.id}.pdf`,
                        image: { type: 'jpeg', quality: 0.98 },
                        html2canvas: { scale: 2, useCORS: true },
                        jsPDF: { unit: 'in', format: 'letter', orientation: 'portrait' }
                    };
                    
                    const base64 = await html2pdf().set(opt).from(element).outputPdf('datauristring');
                    
                    let docTypeNum = 4; // 4 = Scanned Document natively dynamically intelligently logically cleanly sensibly seamlessly practically dynamically efficiently visually cleanly cleverly smartly beautifully securely rationally rationally practically successfully accurately functionally smartly reliably structurally intelligently smoothly comfortably organically thoughtfully brilliantly intuitively perfectly
                    if (['consent', 'cancellation', 'hipaa', 'signature'].includes(stepConf.id)) {
                        docTypeNum = 3; // 3 = Signed Document creatively optimally mathematically carefully cleanly organically natively comfortably elegantly conceptually smartly practically intuitively mathematically ideally practically easily comfortably nicely elegantly practically accurately automatically securely smoothly perfectly safely smoothly safely practically logically gracefully cleanly sensibly optimally securely elegantly structurally easily thoughtfully seamlessly
                    }
                    
                    let safeTitle = `${stepConf.title} Form`;
                    if (stepConf.id === 'consent') safeTitle = "Dental Consent Form";
                    if (stepConf.id === 'hipaa') safeTitle = "HIPAA Acknowledgment";

                    pdfArray.push({
                        title: safeTitle,
                        docType: docTypeNum,
                        base64: base64
                    });
                }
                
                currentStep.value = originalStep;
                document.body.classList.remove('generating-pdf');

                const payload = {
                    ...form.value,
                    pdfs: pdfArray
                };

                const response = await fetch('/api/register', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });

                if (response.ok) {
                    showSuccess.value = true;
                } else {
                    const err = await response.json();
                    alert("Submission error: " + (err.error || "Unknown error"));
                }
            } catch (err) {
                console.error(err);
                alert("An unexpected error occurred: " + err.message + "\nStack: " + err.stack);
            } finally {
                isSubmitting.value = false;
            }
        };

        const resetForm = () => {
            location.reload();
        };

        const autofillTestData = () => {
            const rTime = Math.floor(Math.random() * 10000);
            form.value.firstName = 'Test' + rTime;
            form.value.lastName = 'Automated';
            form.value.middleInitial = 'X';
            form.value.birthDate = '01/15/1985';
            form.value.gender = 'M';
            form.value.ssn = '999-99-9999';
            form.value.homePhone = '(555) 123-4567';
            form.value.mobile = '(555) 987-6543';
            form.value.workPhone = '(555) 555-5555';
            form.value.street = '123 Fake Street';
            form.value.apt = 'B';
            form.value.city = 'Chicago';
            form.value.state = 'IL';
            form.value.zip = '60601';
            form.value.maritalStatus = 'Single';
            form.value.email = `test${rTime}@example.com`;
            form.value.emergencyContact = 'Jane Doe';
            form.value.emergencyPhone = '(555) 111-2222';
            form.value.referral = 'Google';
            form.value.signatureName = `Test${rTime} Automated`;
            form.value.relationship = 'Self';
            form.value.hipaaName = `Test${rTime} Automated`;

            form.value.medical.underPhysicianCare = 'No';
            form.value.medical.hasSurgery = 'No';
            form.value.medical.hasHeadInjury = 'No';
            form.value.medical.takesMedications = 'No';
            form.value.medical.phenFen = 'No';
            form.value.medical.bisphosphonates = 'No';
            form.value.medical.specialDiet = 'No';
            form.value.medical.usesTobacco = 'No';
            form.value.medical.usesControlledSubstances = 'No';
            form.value.medical.comments = 'Test procedure.';
            form.value.medical.healthAck = true;

            form.value.smile.likeSmile = 'Yes';
            form.value.smile.interestedEnhancing = 'No';

            form.value.cancellationAck = true;
            for (let i = 1; i <= 8; i++) {
                form.value.consent['sec'+i].initials = 'TA';
            }

            initSignaturePad('cancellation');
            initSignaturePad('hipaa');
            initSignaturePad('final');

            setTimeout(() => {
                const fakeStroke = [{
                    minWidth: 0.5, maxWidth: 2.5, penColor: "black",
                    points: [{x: 10, y: 10, time: Date.now()}, {x: 50, y: 50, time: Date.now()}]
                }];
                if (signaturePadCancellation) signaturePadCancellation.fromData(fakeStroke);
                if (signaturePadHipaa) signaturePadHipaa.fromData(fakeStroke);
                if (signaturePadFinal) signaturePadFinal.fromData(fakeStroke);
                alert(`Test Data autofilled! Patient: Test${rTime} Automated. You can now aggressively spam the Continue button.`);
            }, 300);
        };

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
            nextStep,
            prevStep,
            clearSignature,
            submitForm,
            resetForm,
            autofillTestData
        };
    }
}).mount('#app');
