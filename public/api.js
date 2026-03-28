window.SYGApi = (() => {
    const backendProfile = {
        id: 'dentimax',
        endpoints: {
            createIntake: '/api/register',
            patientSearch: '/api/patient-search',
            saveCheckIn: '/api/checkin'
        }
    };

    async function requestJson(url, options = {}) {
        const response = await fetch(url, {
            headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
            ...options
        });

        let payload = {};
        try {
            payload = await response.json();
        } catch (err) {
            payload = {};
        }

        if (!response.ok) {
            throw new Error(payload.error || 'Request failed');
        }

        return payload;
    }

    async function searchPatients(criteria) {
        const result = await requestJson(backendProfile.endpoints.patientSearch, {
            method: 'POST',
            body: JSON.stringify(criteria)
        });

        return result.matches || [];
    }

    async function createIntake(payload) {
        return requestJson(backendProfile.endpoints.createIntake, {
            method: 'POST',
            body: JSON.stringify(payload)
        });
    }

    async function saveCheckIn(payload) {
        return requestJson(backendProfile.endpoints.saveCheckIn, {
            method: 'POST',
            body: JSON.stringify(payload)
        });
    }

    return {
        backendProfile,
        searchPatients,
        createIntake,
        saveCheckIn
    };
})();
