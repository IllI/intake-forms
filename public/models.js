window.SYGModels = (() => {
    const defaultSteps = [
        { id: 'registration', title: 'Registration', subtitle: 'Patient Details' },
        { id: 'history', title: 'History', subtitle: 'Medical History' },
        { id: 'conditions', title: 'Conditions', subtitle: 'Health Checklist' },
        { id: 'smile', title: 'Smile', subtitle: 'Cosmetic Questionnaire' },
        { id: 'cancellation', title: 'Cancellation', subtitle: 'Policy Agreement' },
        { id: 'hipaa', title: 'HIPAA', subtitle: 'Privacy Practices' },
        { id: 'consent', title: 'Consent', subtitle: 'Treatment Agreement' },
        { id: 'signature', title: 'Sign', subtitle: 'Finalize' }
    ];

    const allergies = [
        'Aspirin', 'Penicillin', 'Codeine', 'Acrylic', 'Metal', 'Latex', 'Local Anesthetics', 'Sulfa Drugs'
    ];

    const groupedConditions = {
        'Heart & Blood': ['Anemia', 'Angina', 'Artificial Heart Valve', 'Blood Disease', 'Blood Transfusion', 'Bruise Easily', 'Chest Pains', 'Congenital Heart Disorder', 'Emphysema', 'Excessive Bleeding', 'Heart Attack/Failure', 'Heart Murmur', 'Heart Pacemaker', 'Heart Trouble/Disease', 'Hemophilia', 'High Blood Pressure', 'Irregular Heartbeat', 'Low Blood Pressure', 'Mitral Valve Prolapse', 'Rheumatic Fever', 'Sickle Cell Disease', 'Stroke'],
        'Breathing & Lungs': ['Asthma', 'Breathing Problem', 'Easily Winded', 'Frequent Cough', 'Hay Fever', 'Lung Disease', 'Sinus Trouble', 'Tuberculosis'],
        'Brain & Nerves': ["Alzheimer's Disease", 'Convulsions', 'Epilepsy or Seizures', 'Fainting Spells/Dizziness', 'Frequent Headaches', 'Psychiatric Care', 'Spina Bifida'],
        'Metabolic & Digestion': ['Diabetes', 'Excessive Thirst', 'Frequent Diarrhea', 'High Cholesterol', 'Hypoglycemia', 'Kidney Problems', 'Liver Disease', 'Parathyroid Disease', 'Recent Weight Loss', 'Renal Dialysis', 'Stomach/Intestinal Disease', 'Thyroid Disease', 'Ulcers', 'Yellow Jaundice'],
        'Bones & Joints': ['Arthritis/Gout', 'Artificial Joint', 'Osteoporosis', 'Pain in Jaw Joints', 'Rheumatism'],
        'Immunity, Infection & Cancer': ['AIDS/HIV Positive', 'Anaphylaxis', 'Cancer', 'Chemotherapy', 'Cold Sores/Fever Blisters', 'Genital Herpes', 'Hepatitis A', 'Hepatitis B or C', 'Herpes', 'Leukemia', 'Radiation Treatments', 'Scarlet Fever', 'Shingles', 'Tonsillitis', 'Tumors or Growths', 'Venereal Disease'],
        'Other': ['Cortisone Medicine', 'Drug Addiction', 'Glaucoma', 'Hives or Rash', 'Swelling of Limbs']
    };

    function buildEmptyForm() {
        return {
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
                sec1: { checked: false, workDone: [], impacted: '', anesthesia: 'LOCAL', rootCanals: '', other: '', initials: '' },
                sec2: { checked: false, initials: '' },
                sec3: { checked: false, initials: '' },
                sec4: { checked: false, teeth: '', initials: '' },
                sec5: { checked: false, initials: '' },
                sec6: { checked: false, initials: '' },
                sec7: { checked: false, initials: '' },
                sec8: { checked: false, initials: '' }
            },
            cancellationDate: '',
            hipaaDate: '',
            finalDate: ''
        };
    }

    function todayString() {
        const date = new Date();
        return `${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')}/${date.getFullYear()}`;
    }

    function normalizeDate(value) {
        if (!value) return '';
        const parsed = new Date(value);
        if (Number.isNaN(parsed.getTime())) return value;
        return `${String(parsed.getMonth() + 1).padStart(2, '0')}/${String(parsed.getDate()).padStart(2, '0')}/${parsed.getFullYear()}`;
    }

    function buildInitialForm() {
        const form = buildEmptyForm();
        const today = todayString();
        form.cancellationDate = today;
        form.hipaaDate = today;
        form.finalDate = today;
        return form;
    }

    function applyPatientToForm(patient) {
        const form = buildInitialForm();
        const fullName = `${patient.firstName || ''} ${patient.lastName || ''}`.trim();

        form.firstName = patient.firstName || '';
        form.lastName = patient.lastName || '';
        form.birthDate = normalizeDate(patient.birthDate);
        form.gender = patient.gender || '';
        form.homePhone = patient.homePhone || '';
        form.mobile = patient.mobile || '';
        form.street = patient.street || '';
        form.city = patient.city || '';
        form.state = patient.state || 'IL';
        form.zip = patient.zip || '';
        form.email = patient.email || '';
        form.hipaaName = fullName;
        form.signatureName = fullName;

        return form;
    }

    function getConfiguredSteps() {
        const savedConfig = localStorage.getItem('SYG_FORM_CONFIG');
        return savedConfig ? JSON.parse(savedConfig) : defaultSteps;
    }

    return {
        defaultSteps,
        allergies,
        groupedConditions,
        buildEmptyForm,
        buildInitialForm,
        applyPatientToForm,
        getConfiguredSteps,
        todayString,
        normalizeDate
    };
})();
